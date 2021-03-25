#!/usr/bin/env bash

usage="Usage: sh local_deploy.sh (build|update_yarn_package)"

cmd=""

# build related
module=""
buildMode=""
grapeFlag=""

# update hdfs package related
localPackagePath=""
hdfsPackagePath=""

inputCmd()
{
    read -p "build|update_yarn_package: " cmd
}

inputBuildModule()
{
    if [ "$cmd" = "build" ]
    then
        read -p "all|rust|java|deploy_sdk|build_deploy_sdk: " module
    fi
}

inputLocalPackagePath()
{
    if [ "$cmd" = "update_yarn_package" ]
    then
        read -p "maxgraph package local path (/xxx/xxx/0.1.1-snapshot.tar.gz): " localPackagePath
    fi
}

inputHdfsPackagePath()
{
    if [ "$cmd" = "update_yarn_package" ]
    then
        read -p "maxgraph package hdfs path (hdfs://x.x.x.x/tmp/0.1.1-snapshot.tar.gz): " hdfsPackagePath
    fi
}

inputBuildMode()
{
    if [ "${cmd}" = "build" ]; then
        read -p "debug|release: " buildMode
    fi
}

parse2Parameters()
{
    if [ "${cmd}" = "build" ]; then
        module="$1"
    elif [ "$cmd" = "update_yarn_package" ]
    then
        localPackagePath="$1"
    fi
}

parse3Parameters()
{
    if [ "${cmd}" = "build" ]; then
        module="$1"
        buildMode="$2"
    elif [ "$cmd" = "update_yarn_package" ]
    then
        localPackagePath="$1"
        hdfsPackagePath="$2"
    fi
}

parse4Parameters()
{
    if [ "${cmd}" = "build" ]; then
        module="$1"
        buildMode="$2"
        grapeFlag="$3"
    elif [ "$cmd" = "update_yarn_package" ]
    then
        localPackagePath="$1"
        hdfsPackagePath="$2"
    fi
}

case $# in
  (0)
    inputCmd
    inputBuildModule
    inputBuildMode

    inputLocalPackagePath
    inputHdfsPackagePath
    ;;
  (1)
    cmd="$1"
    inputBuildModule
    inputBuildMode

    inputLocalPackagePath
    inputHdfsPackagePath
    ;;
  (2)
    cmd="$1"
    parse2Parameters $2
    inputBuildMode

    inputHdfsPackagePath
    ;;
  (3)
    cmd="$1"
    parse3Parameters $2 $3
    ;;
  (4)
    cmd="$1"
    parse4Parameters $2 $3 $4
    ;;
  (*)
    echo ${usage}
    exit 1
    ;;
esac

if [ "${cmd}" = "build" ]; then
    BIN=`dirname "${BASH_SOURCE-$0}"`
    ROOT_DIR=`cd "${BIN}/../../"; pwd`

    MAXGRAPH_JAVA_DIR="${ROOT_DIR}/src"
    MAXGRAPH_JAVA_SDK_COMMON_DIR="${ROOT_DIR}/src/api/sdk-common"
    MAXGRAPH_JAVA_SDK_DIR="${ROOT_DIR}/src/client/sdk"
    MAXGRAPH_JAVA_GREMLIN_SDK="${ROOT_DIR}/src/client/maxgraph-gremlin-sdk"
    MAXGRAPH_RUST_DIR="${ROOT_DIR}/src"
    BUILD_OUTPUT_DIR="${ROOT_DIR}/build"
    mkdir -p ${BUILD_OUTPUT_DIR}

    MVN_CMD=`which mvn`

    cd "${MAXGRAPH_JAVA_DIR}"
    # NOTE: get version from pom.xml
    PACKAGE_DIR=`sed -n '17p' pom.xml | awk -F '>' '{print $2}' | awk -F '<' '{print $1}'`
    echo "PACKAGE_DIR(project.version in pom) is: ${PACKAGE_DIR}"
    PACKAGE_NAME="${PACKAGE_DIR}.tar.gz";
    PACKAGE_FILE_PATH="${MAXGRAPH_JAVA_DIR}/assembly/target/${PACKAGE_NAME}"
fi


checkMVN()
{
    if [ "${MVN_CMD}" = "" ]
    then
        echo "mvn not set"
        exit 1
    fi

    echo "use mvn cmd: ${MVN_CMD}"
}

checkHadoop()
{
    if [ "${HADOOP_HOME}" = "" ]
    then
        echo "hadoop home not set"
        exit 1
    fi

    echo "use mvn cmd: ${MVN_CMD}"
}

checkJDK()
{
    if [ "${JAVA_HOME}" = "" ]; then
        echo "JAVA_HOME not set"
        exit 1
    fi

    isMatch=`${JAVA_HOME}/bin/java -version 2>&1 | grep 1.8`
    if [ "$isMatch" = "" ]; then
        echo "Java 8 is required!"
    fi
}

checkStatus()
{
    resultCode=$1
    errMsg=$2
    if [ ${resultCode} -ne 0 ]
    then
        echo "===${errMsg}==="
        exit 1
    fi
}

checkFileExist()
{
    filePath=$1
    errMsg=$2
    if [ ! -f "${filePath}" ]
    then
        echo "===${errMsg}==="
        exit 1
    fi
}

buildJavaProject()
{
    checkMVN
    # maven package java project
    cd "${MAXGRAPH_JAVA_DIR}"
    ${MVN_CMD} clean install -DskipTests -P java-release
    checkStatus $? "maven build java project error"
    checkFileExist ${PACKAGE_FILE_PATH} "java tar.gz package not found, ${PACKAGE_FILE_PATH}"

    cd "${BUILD_OUTPUT_DIR}"
    packageDir="${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}"
    if [ ! -d ${packageDir} ]
    then
        rm -rf "./${PACKAGE_DIR}*"
        rm -f "./*.tar.gz"
        cp ${PACKAGE_FILE_PATH} .
        tar -xzf ${PACKAGE_NAME}
#        rm -f ${PACKAGE_DIR}/lib/maxgraph-loader-*.jar
        rm -f ${PACKAGE_DIR}/lib/original-maxgraph-loader-*-SNAPSHOT.jar
        rm -rf ${PACKAGE_DIR}/apsara_libs
        rm -f apsara_libs.tar.gz
        wget http://cn-hangzhou.oss.aliyun-inc.com/graphcompute/maxgraph_package/pangufs/apsara_libs.tar.gz
        tar -zxf apsara_libs.tar.gz -C ${PACKAGE_DIR}/
        rm -f apsara_libs.tar.gz
    else
        echo "package dir exist, and just update java lib"
        rm -rf ./tmp
        mkdir ./tmp
        cd ./tmp
        cp ${PACKAGE_FILE_PATH} .
        tar -xzf "${PACKAGE_FILE_PATH}"
        cd ..
        rm -rf ${PACKAGE_DIR}/lib
        rm -rf ${PACKAGE_DIR}/script
#        rm -f ./tmp/${PACKAGE_DIR}/lib/maxgraph-loader-*.jar
        rm -f ./tmp/${PACKAGE_DIR}/lib/original-maxgraph-loader-*-SNAPSHOT.jar
        cp -r ./tmp/${PACKAGE_DIR}/lib ${PACKAGE_DIR}
        cp -r ./tmp/${PACKAGE_DIR}/script ${PACKAGE_DIR}
        rm -f "${PACKAGE_NAME}"
        tar -czf "${PACKAGE_NAME}" ${PACKAGE_DIR}
        rm -rf ./tmp
    fi
    # make shell script executable
    chmod a+x ${PACKAGE_DIR}/script/yarn_start_executor.sh
    cp ${MAXGRAPH_JAVA_DIR}/assembly/conf/log4j2.xml ${PACKAGE_DIR}/conf

    cp -r ${MAXGRAPH_JAVA_DIR}/admin-service/maxgraph-studio-start/target/studio ${MAXGRAPH_JAVA_DIR}/admin-service/maxgraph-studio-start/target/maxgraph-web

    echo "build java success and current package size:"`du -sh "${PACKAGE_FILE_PATH}"`
}

executeBuild()
{
    if [ "${buildMode}" = "release" ]
    then
        cd ${MAXGRAPH_RUST_DIR}/executor/ && sh exec.sh cargo build --all --release
    else
        cd ${MAXGRAPH_RUST_DIR}/executor/ && sh exec.sh cargo build --all
    fi
}

STORE_PACKAGE_NOT_EXIST="not exist"
isStorePossibleBinary()
{
    filePath=$1
    if [ ! -f "${filePath}" ]
    then
        echo ${STORE_PACKAGE_NOT_EXIST}
    else
        echo "exist"
    fi
}

buildRust()
{
    # cargo build store project
    cd "${MAXGRAPH_RUST_DIR}"
    if [ "${grapeFlag}" == "TRUE" ]
    then
        echo "Build rust with grape"
        # check libvineyard_client.a exist
        rm -rf ${MAXGRAPH_RUST_DIR}/libvineyard_client.a*
        wget http://graphcompute.cn-hangzhou.oss.aliyun-inc.com/vineyard/libvineyard_client.a
        if [ -f "${MAXGRAPH_RUST_DIR}/libvineyard_client.a" ]; then
            echo "Build with vineyard lib"
            export VINEYARD_LIB_PATH=${MAXGRAPH_RUST_DIR}
        fi
    else
        echo "Build rust without grape"
    fi


    executeBuild
    checkStatus $? "cargo build rust project error"

    possibleStoreBinaryNameArray=("executor")
    mkdir -p "${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}/bin"

    isBinaryExist=${STORE_PACKAGE_NOT_EXIST}
    for binaryName in ${possibleStoreBinaryNameArray[@]}
    do
    {
        binaryPath="${MAXGRAPH_RUST_DIR}/executor/target/${buildMode}/${binaryName}"
        binaryStatus=`isStorePossibleBinary ${binaryPath}`
        echo "===${binaryName} ${binaryStatus}==="

        if [ "${binaryStatus}" != "${STORE_PACKAGE_NOT_EXIST}" ]
        then
            isBinaryExist="exist"
            rm -rf "${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}/bin/${binaryName}"
            cp ${binaryPath} "${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}/bin"
        fi
    }
    done

    if [ "${isBinaryExist}" = "${STORE_PACKAGE_NOT_EXIST}" ]
    then
        echo "===build store failed==="
        exit 1
    fi

    # idServiceBinaryPath="${MAXGRAPH_RUST_DIR}/id-service/target/${buildMode}/id-service"
    # checkFileExist ${idServiceBinaryPath} "id-service binary not found"

    cd "${BUILD_OUTPUT_DIR}"
    # cp "${idServiceBinaryPath}" "${PACKAGE_DIR}/bin"
    cp "${MAXGRAPH_RUST_DIR}/executor/store/log4rs.yml" "${PACKAGE_DIR}/conf"

    # add so into native dir
    # odpsTunnelSoPath="${MAXGRAPH_RUST_DIR}/common/rust/ffi/tunnel-rust/native/build/lib/libodps_tunnel.so"
    # checkFileExist ${odpsTunnelSoPath} "libodps_tunnel.so not found"
    # odpsWrapperSoPath="${MAXGRAPH_RUST_DIR}/common/rust/ffi/tunnel-rust/native/build/lib/libtunnel_wrapper.so"
    # checkFileExist ${odpsWrapperSoPath} "libtunnel_wrapper.so not found"
    pbSoDir="${MAXGRAPH_RUST_DIR}/common/rust/ffi/tunnel-rust/native/third_party/protobuf-2.4.1/lib"

    nativeSoDir="${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}/native"
    rm -rf ${nativeSoDir}
    mkdir -p "${nativeSoDir}"

    # cp ${odpsTunnelSoPath} ${nativeSoDir}
    # cp ${odpsWrapperSoPath} ${nativeSoDir}
    cp -r ${pbSoDir}/* ${nativeSoDir}

#    jnaLibName="libmaxgraph_jna.so"
#    isJnaLibExist=${STORE_PACKAGE_NOT_EXIST}
#    jnaLibPath="${MAXGRAPH_RUST_DIR}/executor/target/${buildMode}/${jnaLibName}"
#    jnaLibStatus=`isStorePossibleBinary ${jnaLibPath}`
#    if [ "${jnaLibStatus}" != "${STORE_PACKAGE_NOT_EXIST}" ]
#    then
#        isJnaLibExist="exist"
#        rm -rf "${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}/native/${jnaLibName}"
#        cp ${jnaLibPath} "${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}/native"
#    fi
#
#    if [ "${isJnaLibExist}" = "${STORE_PACKAGE_NOT_EXIST}" ]
#    then
#        echo "===build store failed==="
#        exit 1
#    fi

    rm -f "${PACKAGE_NAME}"
    tar -czf "${PACKAGE_NAME}" "${PACKAGE_DIR}"

    echo "build store success and current package size:"`du -sh "${PACKAGE_NAME}"`
}

replaceConfFile()
{
    file=$1
    src=$2
    dst=$3
    rm -f tmp.properties
    sed "s:${src}:${dst}:g" ${file} > tmp.properties
    rm -f ${file}
    mv tmp.properties ${file}
}

updateConfig()
{
    confFileName=$1
    cd "${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}"

    replaceConfFile conf/${confFileName} "0.0.1-SNAPSHOT" ${PACKAGE_DIR}
    loadJarPath="${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}/lib/maxgraph-loader-${PACKAGE_DIR}.jar"
    replaceConfFile conf/${confFileName} "graph.loader.jar=.*" "graph.loader.jar=${loadJarPath}"
    localPackagePath="local.package.path=${BUILD_OUTPUT_DIR}/${PACKAGE_NAME}"
    replaceConfFile conf/${confFileName} "local.package.path=.*" "${localPackagePath}"
}

checkPackageDirExist()
{
    packageDirPath="${BUILD_OUTPUT_DIR}/${PACKAGE_DIR}"
    if [ ! -d ${packageDirPath} ]
    then
        buildJavaProject
    fi
}

deploy_sdk() {
    checkMVN
    checkJDK

    cd "$ROOT_DIR"

    ## deploy parent pom
    ${MVN_CMD} -N source:jar deploy -DskipTests

    cd "$MAXGRAPH_JAVA_SDK_COMMON_DIR"
    ${MVN_CMD} source:jar deploy -DskipTests

    checkStatus $? "deploy sdk common error"

    cd "$MAXGRAPH_JAVA_SDK_DIR"
    ${MVN_CMD} source:jar deploy -DskipTests

    cd "$MAXGRAPH_JAVA_GREMLIN_SDK"
    ${MVN_CMD} source:jar deploy -DskipTests

    checkStatus $? "deploy sdk error"
}

build()
{
    case ${module} in
      (all)
        buildJavaProject
        buildRust
        ;;
      (java)
        buildJavaProject
        ;;
      (build_deploy_sdk)
        buildJavaProject
        deploy_sdk
        ;;
      (deploy_sdk)
        deploy_sdk
        ;;
      (rust)
        checkPackageDirExist
        buildRust
        ;;
      (*)
        echo "illegal module name:${module}"
        exit 1
        ;;

    esac
}

updateHdfsPackage()
{
    ${HADOOP_HOME}/bin/hadoop fs -rm ${hdfsPackagePath}
    ${HADOOP_HOME}/bin/hadoop fs -copyFromLocal ${localPackagePath} ${hdfsPackagePath}
}

case ${cmd} in

  (build)
    build
    ;;
  (update_yarn_package)
    updateHdfsPackage
    ;;
  (*)
    echo ${usage}
    exit 1
    ;;

esac
