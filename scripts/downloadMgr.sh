#!/bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2018 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

if [ -f /etc/device.properties ];then
    . /etc/device.properties
fi

if [ -f /etc/rdm/downloadUtils.sh ];then
    . /etc/rdm/downloadUtils.sh
else
    echo "File Not Found, /etc/rdm/downloadUtils.sh"
fi

RDM_SSR_LOCATION=/tmp/.rdm_ssr_location
RDM_DOWNLOAD_PATH=/tmp/rdm/
PEER_COMM_DAT="/etc/dropbear/elxrretyt.swr"
PEER_COMM_ID="/tmp/elxrretyt-$$.swr"
CONFIGPARAMGEN=/usr/bin/configparamgen
APPLN_HOME_PATH=/tmp/${DOWNLOAD_APP_MODULE}
DOWNLOAD_MGR_PIDFILE=${APPLN_HOME_PATH}/.dlApp${DOWNLOAD_APP_MODULE}.pid
# Ensure only one instance of script is running
if [ -f $DOWNLOAD_MGR_PIDFILE ];then
   pid=`cat $DOWNLOAD_MGR_PIDFILE`
   if [ -d /proc/$pid ];then
      log_msg "Another instance of this app $0 is already running..!"
      log_msg "Exiting without starting the $0..!"
      exit 0
   fi
else
   echo $$ > $DOWNLOAD_MGR_PIDFILE
fi

usage()
{
    log_msg "USAGE: $0 <APPLICATION NAME> <APPICATION HOME PATH> <DOWNLOAD VALIDATION METHOD> <PACKAGE EXTN (.ipk or .bin or .tar ) <PACKAGE NAME> >"
    log_msg "Mandatory Arguments: <APPLICATION NAME> <DOWNLOAD VALIDATION METHOD>"
    log_msg "Optional Arguments: <APPLICATION HOME PATH>, Default Value /tmp/<APPLICATION NAME>"
    log_msg "Optional Arguments: <PACKAGE NAME>, if not default to <APPLICATION NAME>.<PACKAGE EXTN>"
    log_msg "Optional Arguments: <PACKAGE EXTN>, if not default to <APPLICATION NAME>.ipk"
}

# Input Arguments Validation
# Input Argument: Application Name (Mandatory Field)
if [ ! "$1" ];then
     log_msg "Application Name is Empty, Execute Once Again `basename $0` "
     usage
     exit 0
else
     DOWNLOAD_APP_MODULE="$1"
fi

# Input Parameter: Application Home Path
if [ ! "$2" ];then
      APPLN_HOME_PATH=/tmp/$DOWNLOAD_APP_MODULE
else
      log_msg "using the custom HOME path:$2"
      APPLN_HOME_PATH=$2
fi

# Input Parameter: Authentication Method for Package Validation
if [ ! "$3" ];then
      log_msg "Application Download Not possible without Authentication"
      log_msg "Supported Authentications: KMS Signature Validation and OpenSSL Verifications"
      usage
      exit 1
else
      PKG_AUTHENTICATION=$3
fi

# Input Parameter: Package Extension
if [ ! $4 ];then
     PACKAGE_EXTN="ipk"
     log_msg "Using Default Package Extension $PACKAGE_EXTN"
else
     PACKAGE_EXTN=$4
     log_msg "Package Extension is $PACKAGE_EXTN"
fi
downloadApp_getVersionPrefix()
{
   buildType=`downloadApp_getBuildType`
   version=$(downloadApp_getFWVersion)
   versionPrefix=`echo $version | sed 's/_'$buildType'//g'`
   echo $versionPrefix
}

# Extract the App file name from /version.txt
downloadApp_getFWVersion()
{
    versionTag1=$FW_VERSION_TAG1
    versionTag2=$FW_VERSION_TAG2
    verStr=`cat /version.txt | grep ^imagename:$versionTag1`
    if [ $? -eq 0 ];then
         version=`echo $verStr | cut -d ":" -f2`
    else
         version=`cat /version.txt | grep ^imagename:$versionTag2 | cut -d ":" -f2`
    fi
    echo $version
}

# identifies whether it is a VBN or PROD build
downloadApp_getBuildType()
{
    str=$(downloadApp_getFWVersion)
    echo $str | grep -q 'VBN'
    if [[ $? -eq 0 ]] ; then
          echo 'VBN'
          exit 0
    fi
    echo $str | grep -q 'PROD'
    if [[ $? -eq 0 ]] ; then
          echo 'PROD'
          exit 0
    fi
    echo $str | grep -q 'QA'
    if [[ $? -eq 0 ]] ; then
           echo 'QA'
           exit 0
    fi
    echo $str | grep -q 'DEV'
    if [[ $? -eq 0 ]] ; then
          echo 'DEV'
          exit 0
    fi
    echo $str | grep -q 'VBN_BCI'
    if [[ $? -eq 0 ]] ; then
          echo 'VBN'
          exit 0
    fi
    echo $str | grep -q 'PROD_BCI'
    if [[ $? -eq 0 ]] ; then
          echo 'PROD'
          exit 0
    fi
    echo $str | grep -q 'DEV_BCI'
    if [[ $? -eq 0 ]] ; then
          echo 'DEV'
          exit 0
    fi
}

# Generating the Download Package Name from Version.txt
if [ ! $5 ];then
     log_msg "Package Name from meta data: /etc/rdm/rdm-manifest.xml"
     # Retrive the Appln metadata
     DOWNLOAD_PKG_NAME=`xmllint --xpath "//application_list/$DOWNLOAD_APP_MODULE/package_name/text()" /etc/rdm/rdm-manifest.xml` 
     log_msg "Meta-data: package name: $DOWNLOAD_PKG_NAME"
else
     DOWNLOAD_PKG_NAME=$5
     applicationSuffix="${DOWNLOAD_PKG_NAME}-signed"
     DOWNLOAD_PKG_NAME="${applicationSuffix}.tar"
     log_msg "Using the custom Package name: $DOWNLOAD_PKG_NAME"
fi

log_msg "DOWNLOAD_APP_MODULE = $DOWNLOAD_APP_MODULE"
log_msg "PKG_AUTHENTICATION = $PKG_AUTHENTICATION"
log_msg "PKG_EXTN = $PKG_EXTN"

DOWNLOAD_APP_NAME=`xmllint --xpath "//application_list/$DOWNLOAD_APP_MODULE/app_name/text()" /etc/rdm/rdm-manifest.xml` 
log_msg "Meta-data: package name: $DOWNLOAD_APP_NAME"
DOWNLOAD_APP_SIZE=`xmllint --xpath "//application_list/$DOWNLOAD_APP_MODULE/app_size/text()" /etc/rdm/rdm-manifest.xml` 
log_msg "Meta-data: package size: $DOWNLOAD_APP_SIZE"

if [ ! "$DOWNLOAD_APP_NAME" ];then
    DOWNLOAD_APP_NAME=$DOWNLOAD_APP_MODULE
fi

# Setup the workspace
APPLN_HOME_PATH=/tmp/${DOWNLOAD_APP_NAME}
DOWNLOAD_MGR_PIDFILE=${APPLN_HOME_PATH}/.dlApp${DOWNLOAD_APP_MODULE}.pid
DOWNLOAD_LOCATION=$RDM_DOWNLOAD_PATH/downloads/$DOWNLOAD_APP_NAME
if [ ! -d $DOWNLOAD_LOCATION ];then
       mkdir -p $DOWNLOAD_LOCATION
fi

log_msg "APPLN_HOME_PATH = $APPLN_HOME_PATH"
## Retry Interval in seconds
DOWNLOAD_APP_RETRY_DELAY=30
## Maximum Retry Count
DOWNLOAD_APP_RETRY_COUNT=3
DOWNLOAD_APP_PROGRESS_FLAG="${APPLN_HOME_PATH}/.dlAppInProgress"
## File to save http code
DOWNLOAD_APP_HTTP_OUTPUT="$APPLN_HOME_PATH/download_httpoutput"
## File to save curl/wget response
DOWNLOAD_APP_HTTP_RESPONSE="$APPLN_HOME_PATH/download_http_response"
# URL Location for Download

# TODO Will Update after RFC changes
DOWNLOAD_APP_SSR_LOCATION=/nvram/.download_ssr_location

CURL_TIMEOUT=10
CURL_OPTION="-w"
TLS="--tlsv1.2"
CURL_TLS_TIMEOUT=30
downloadStatus=1

HTTP_CODE="$APPLN_HOME_PATH/httpcode"
RETRY_STATUS=1
http_code=1

sendDownloadRequest()
{
    status=1
    counter=0
    curl_request=$1
    while [ $status -ne 0 ]
    do
        log_msg "sendDownloadRequest: URL_CMD: ${curl_request}"
        eval $curl_request > $HTTP_CODE
        status=$?
        http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
        if [ $status -ne 0 ];then
            echo "sendDownloadRequest: Package download http_code : $http_code   ret : $status"
            if [ -f $DOWNLOAD_LOCATION/$downloadFile ];then
                  log_msg "sendDownloadRequest: Curl partial Download, Failed download for $downloadUrl"
                  rm $DOWNLOAD_LOCATION/$downloadFile
            else
                  log_msg "sendDownloadRequest: Curl Download Failed for $downloadUrl"
            fi
            counter=`expr $counter + 1`
            log_msg "sendDownloadRequest: Retry: $counter"
            if [ $counter -eq 3 ];then
                log_msg "sendDownloadRequest: 3 retries failed, exiting from retry..!"
                status=0
                break
            else
 		# Needs to be less sleep, Since it causes holdoff expiry of MeshAgent.service
                sleep 10
            fi
        else
            echo "sendDownloadRequest: Package download http_code : $http_code   ret : $status"
            if [ "$http_code" = "200" ]; then
                  downloadStatus=0
                  RETRY_STATUS=0
                  log_msg "sendDownloadRequest: Curl Download Success for $downloadUrl"
                  status=0
            fi
        fi
    done
}

applicationDownload()
{
    downloadUrl=$1
    downloadStatus=1
    downloadFile=`basename $downloadUrl`
    log_msg "applicationDownload: DOWNLOADING: tar file $downloadUrl"
    TLS="--tlsv1.2"
    IF_OPTION=""
    if [ "$DEVICE_TYPE" = "broadband" ] && [ "$MULTI_CORE" = "yes" ];then
          core_output=`get_core_value`
          if [ "$core_output" = "ARM" ];then 
                IF_OPTION="--interface $ARM_INTERFACE"
          fi
    fi

    CURL_CMD="curl $TLS $IF_OPTION -fgL $CURL_OPTION '%{http_code}\n' -o \"$DOWNLOAD_LOCATION/$downloadFile\" \"$downloadUrl\" --connect-timeout $CURL_TLS_TIMEOUT -m 20"
    echo $CURL_CMD
    sendDownloadRequest "${CURL_CMD}"
    
    if [ $RETRY_STATUS -ne 0 ] && [ "$http_code" == "000" ] && [ -f /usr/bin/configparamgen ];then
         # Retry image download attempts via CodeBig
           log_msg "Failed to download image from normal SSR CDN server"
           log_msg "Retrying to communicate with SSR via CodeBig server"
           domainName=`echo $downloadUrl | awk -F/ '{print $3}'`
           imageHTTPURL=`echo $downloadUrl | sed -e "s|.*$domainName||g"`
           SIGN_CMD="configparamgen 1 \"$imageHTTPURL\""
           eval $SIGN_CMD > /tmp/.signedRequest
           cbSignedimageHTTPURL=`cat /tmp/.signedRequest`
           rm -f /tmp/.signedRequest
           # Work around for resolving SSR url encoded location issue
           # Correcting stb_cdl location in CB signed request 
           cbSignedimageHTTPURL=`echo $cbSignedimageHTTPURL | sed 's|stb_cdl%2F|stb_cdl/|g'`
           serverUrl=`echo $cbSignedimageHTTPURL | sed -e "s|&oauth_consumer_key.*||g"`
           authorizationHeader=`echo $cbSignedimageHTTPURL | sed -e "s|&|\", |g" -e "s|=|=\"|g" -e "s|.*oauth_consumer_key|oauth_consumer_key|g"`
           authorizationHeader="Authorization: OAuth realm=\"\", $authorizationHeader\""
           CURL_CMD="curl $TLS $IF_OPTION -fgL --connect-timeout $CURL_TLS_TIMEOUT  -H '$authorizationHeader' -w '%{http_code}\n' -o \"$DOWNLOAD_LOCATION/$downloadFile\" '$serverUrl' > $HTTP_CODE"
           sendDownloadRequest "$CURL_CMD"
    fi
}

applicationExtraction()
{
    downloadUrl=$1
    downloadFile=`basename $downloadUrl`
    if [ ! -f $DOWNLOAD_LOCATION/$downloadFile ];then
           downloadStatus=1
           log_msg  "applicationExtraction: File Not Found for Extraction: $DOWNLOAD_LOCATION/$downloadFile"
           exit 2
    fi
    tar -xvf $DOWNLOAD_LOCATION/$downloadFile -C $DOWNLOAD_LOCATION/
    if [ $? -ne 0 ];then
            log_msg "applicationExtraction: $downloadFile: tar Extraction Failed..!"
            exit 2
    fi
    if [ -f $DOWNLOAD_LOCATION/$downloadFile ];then
    	log_msg "applicationExtraction: Removing The Downloaded File After Extraction [$DOWNLOAD_LOCATION/$downloadFile]"
 	rm -rf $DOWNLOAD_LOCATION/$downloadFile
    fi
}

# setup the workspace and initial cleanup
if [ ! -d $APPLN_HOME_PATH ];then
     mkdir -p $APPLN_HOME_PATH
fi

# Setup the Download Path
if [ ! -d $DOWNLOAD_LOCATION ]; then
      mkdir -p $DOWNLOAD_LOCATION
else
     # Remove the previously download files
     rm -f $DOWNLOAD_LOCATION/*
fi

#Setup the URL Location for RDM packages
ARM_SCP_IP_ADRESS=$ARM_INTERFACE_IP
if [ ! $ARM_SCP_IP_ADRESS ];then
      log_msg "Either Missing ARM SCP IP ADDRESS , Please Check /etc/device.properties "
      log_msg "             Or               "
      log_msg "Platform with Single Processor "
      log_msg "             Or               "
      log_msg "Processes are running on the ATOM side "
fi

if [ -f /tmp/.xconfssrdownloadurl ];then
           cp /tmp/.xconfssrdownloadurl /tmp/.rdm_ssr_location
           cp /tmp/.rdm_ssr_location /nvram/.rdm_ssr_location
else
           status=1
           counter=0
           log_msg "DOWNLOADING: /tmp/.xconfssrdownloadurl from ARM Side"
           $CONFIGPARAMGEN jx $PEER_COMM_DAT $PEER_COMM_ID
           while [ $status -eq 1 ]
           do
                scp -i $PEER_COMM_ID root@$ARM_SCP_IP_ADRESS:/tmp/.xconfssrdownloadurl $RDM_SSR_LOCATION
                status=$?
                if [ $status -eq 0 ] && [ -f $RDM_SSR_LOCATION ];then
                     cp $RDM_SSR_LOCATION /nvram/.rdm_ssr_location
                else
                     log_msg "scp failed for /tmp/.xconfssrdownloadurl, Please Check Firmware Upgrade Status at ARM side"
                     sleep 5
                fi
                counter=`expr $counter + 1`
                if [ $counter -eq 3 ];then
                     status=0
                     if [ -f /nvram/.rdm_ssr_location ];then
                          cp /nvram/.rdm_ssr_location /tmp/.rdm_ssr_location
                     fi
                fi
          done
          rm -f $PEER_COMM_ID
fi

if [ ! -f $RDM_SSR_LOCATION ];then
        log_msg "$RDM_SSR_LOCATION SSR URL Location Input File is not there"
        exit 1
elif [ ! -s $RDM_SSR_LOCATION ];then
        log_msg "Download URL is empty Inside $RDM_SSR_LOCATION"
        exit 1
else
        url=`cat $RDM_SSR_LOCATION`
        log_msg "RDM App Download URL Location is $url"
fi

# Download the File Package
log_msg "Downloading The Package $url/${DOWNLOAD_PKG_NAME}"
applicationDownload $url/${DOWNLOAD_PKG_NAME}

if [ "$DOWNLOAD_APP_SIZE" ];then
     sizeVal=$DOWNLOAD_APP_SIZE
     scale=`echo "${sizeVal#"${sizeVal%?}"}"`
     value=`echo ${sizeVal%?}`

     floatNum="${value//[^.]}"
     if [ $floatNum ];then
          factor=1024
          case $scale in
            "G"|"g")
               log_msg "App Size is in GigaBytes"
               t=$(echo $factor $value | awk '{printf "%4.3f\n",$1*$2}')
               tx=`echo $t | cut -d '.' -f1`
               t=`expr $tx + 1`
               FINAL_DOWNLOAD_APP_SIZE=${t}M
               log_msg "App Size converted from $DOWNLOAD_APP_SIZE to $FINAL_DOWNLOAD_APP_SIZE"
               ;;
            "M"|"m")
               log_msg "App Size is in MegaBytes"
               t=$(echo $factor $value | awk '{printf "%4.3f\n",$1*$2}')
               tx=`echo $t | cut -d '.' -f1`
               t=`expr $tx + 1`
               FINAL_DOWNLOAD_APP_SIZE=${t}K
               log_msg "App Size converted from $DOWNLOAD_APP_SIZE to $FINAL_DOWNLOAD_APP_SIZE"
               ;;
            "K"|"k")
               log_msg "App Size is in KiloBytes"
               t=$(echo $factor $value | awk '{printf "%4.3f\n",$1*$2}')
               tx=`echo $t | cut -d '.' -f1`
               t=`expr $tx + 1`
               FINAL_DOWNLOAD_APP_SIZE=${t}B
               log_msg "App Size converted from $DOWNLOAD_APP_SIZE to $FINAL_DOWNLOAD_APP_SIZE"
               ;;
            "*")
               log_msg "Wrong Measurement Unit for App Size (nB/nK/nM/nG)"
               exit
               ;; 
         esac
     else
         FINAL_DOWNLOAD_APP_SIZE=$value$scale
         log_msg "App Size is $FINAL_DOWNLOAD_APP_SIZE"
     fi
     if [ -d $APPLN_HOME_PATH ];then rm -rf $APPLN_HOME_PATH/* ; fi
     mountFlag=`mount | grep $APPLN_HOME_PATH`
     if [ "$mountFlag" ];then umount $APPLN_HOME_PATH ; fi
     mount -t tmpfs -o size=$FINAL_DOWNLOAD_APP_SIZE -o mode=544 tmpfs $APPLN_HOME_PATH
fi 

# Extract the Package
log_msg "Extracting The Package $url/${DOWNLOAD_PKG_NAME}"
applicationExtraction $url/${DOWNLOAD_PKG_NAME}

#package_tarFile=`ls $APPLN_HOME_PATH/*-pkg.tar| xargs basename`
package_tarFile=`ls $DOWNLOAD_LOCATION/*-pkg.tar| xargs basename`
log_msg "Intermediate PKG File: $package_tarFile"
if [ $package_tarFile ] && [ -f $DOWNLOAD_LOCATION/$package_tarFile ];then
      ls -l $DOWNLOAD_LOCATION/$package_tarFile
      hashVal=`sha256sum $DOWNLOAD_LOCATION/$package_tarFile | cut -d " " -f1`
      tar -xvf $DOWNLOAD_LOCATION/$package_tarFile -C $DOWNLOAD_LOCATION/
fi

package_signatureFile=`ls $DOWNLOAD_LOCATION/*-pkg.sig| xargs basename`
if [ $package_signatureFile ];then
       if [ -f $DOWNLOAD_LOCATION/$package_signatureFile ];then
            signVal=`cat $DOWNLOAD_LOCATION/$package_signatureFile`
       fi
fi

package_keyFile=`ls $DOWNLOAD_LOCATION/*nam.txt| xargs basename`
if [ $package_keyFile ];then
       if [ -f $DOWNLOAD_LOCATION/$package_keyFile ];then
            keyVal=`head -n1  $DOWNLOAD_LOCATION/$package_keyFile`
       fi
fi

# Signature Validation
if [ "$PKG_AUTHENTICATION" = "kms" ];then
     log_msg "KMS Validation on the Package"
     #kmsVerification $keyVal $hashVal $signVal
     sh /etc/rdm/kmsVerify.sh ${DOWNLOAD_LOCATION} $keyVal $hashVal $signVal
elif [ "$PKG_AUTHENTICATION" = "openssl" ];then
     log_msg "openSSL Validation on the Package"
     sh /etc/rdm/opensslVerifier.sh ${DOWNLOAD_LOCATION}/ $package_tarFile $package_signatureFile "kms"
else
     log_msg "Application Download Not possible without Authentication"
     log_msg "Supported Authentications: KMS Signature Validation and OpenSSL Verifications"
fi

if [ $? -ne 0 ];then
     log_msg "signature validation failed"
     rm -rf $DOWNLOAD_LOCATION/$package_tarFile
     rm -rf $DOWNLOAD_LOCATION/$package_signatureFile
     rm -rf $DOWNLOAD_LOCATION/$package_keyFile
     rm -rf $DOWNLOAD_LOCATION/*
fi

log_msg "Package Download Success"

log_msg "$APPLN_HOME_PATH/ CleanUp"
rm -rf $DOWNLOAD_LOCATION/$package_tarFile
rm -rf $DOWNLOAD_LOCATION/$package_signatureFile
rm -rf $DOWNLOAD_LOCATION/$package_keyFile

CURRENT_PATH=`pwd` 
cd $DOWNLOAD_LOCATION

if [ -f $DOWNLOAD_LOCATION/packages.list ];then
      while read -r finalPackage
      do
          extension="${finalPackage##*.}"
          log_msg "Extracting the Package: ${finalPackage} ${extension}"
          case "${extension}" in
          ipk )
               ar -x $finalPackage
               umask 544
               tar -xzvf data.tar.gz -C $APPLN_HOME_PATH/
               if [ -f $DOWNLOAD_LOCATION/debian-binary ];then
                    rm -rf $DOWNLOAD_LOCATION/debian-binary
               fi
               if [ -f $DOWNLOAD_LOCATION/control.tar.gz ];then
                    rm -rf $DOWNLOAD_LOCATION/control.tar.gz
               fi
               if [ -f $DOWNLOAD_LOCATION/data.tar.gz ];then
                    rm -rf $DOWNLOAD_LOCATION/data.tar.gz
               fi
          ;;
          tar )
              tar -xvf $finalPackage -C $APPLN_HOME_PATH/
          ;;
          *)
             log_msg "Unknown Package Extension"
             break
          ;;
          esac
          if [ -f ./${finalPackage} ];then
               log_msg "Removing $finalPackage after Extraction"
               rm -rf ./$finalPackage
          fi
      done <$DOWNLOAD_LOCATION/packages.list
else
      log_msg "Not Found the Packages List file"
      rm -rf $DOWNLOAD_LOCATION/*
      exit 0
fi
chmod -R 544 $APPLN_HOME_PATH/
log_msg "Download and Extraction Completed"
cd $CURRENT_PATH
exit 0
