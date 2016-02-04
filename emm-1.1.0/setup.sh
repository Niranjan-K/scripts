#!/bin/sh  
# source the properties:  
. ./config.properties  

###################### Validation ######################
set -e #stop if there is an error

if ! [ -f $OPENSSL_CONFIG_FILE ]; then
	echo "Openssl Config File does not exist: "$OPENSSL_CONFIG_FILE
	exit
fi

if ! [ -f $BKS_CONVERTER ]; then
	echo "BKS Converter JAR file does not exist: "$OPENSSL_CONFIG_FILE
	exit
fi

if [ -d $TEMP_FOLDER ]; then
	rm -rf $TEMP_FOLDER
fi
mkdir $TEMP_FOLDER

if [ -d $OUTPUT_FOLDER ]; then
	rm -rf $OUTPUT_FOLDER
fi
mkdir $OUTPUT_FOLDER

unamestr=`uname`
if [ $unamestr = "Linux" ]; then
	SED_OS_PARAMETER=''
elif [ $unamestr == "Darwin" ]; then
	SED_OS_PARAMETER=\'\'
fi

if [ -z $SSL_SERIAL ]; then
	SSL_SERIAL=$(date +%s)
fi

###################### Certificate Generation  ############################################

CA_SUBJ="/C="$CA_COUNTRY"/ST="$CA_STATE"/L="$CA_LOCALITY"/O="$CA_ORGANISATION"/OU="$CA_ORGANISATIONUNIT"/CN="$CA_COMMONNAME
RA_SUBJ="/C="$RA_COUNTRY"/ST="$RA_STATE"/L="$RA_LOCALITY"/O="$RA_ORGANISATION"/OU="$RA_ORGANISATIONUNIT"/CN="$RA_COMMONNAME
SSL_SUBJ="/C="$SSL_COUNTRY"/ST="$SSL_STATE"/L="$SSL_LOCALITY"/O="$SSL_ORGANISATION"/OU="$SSL_ORGANISATIONUNIT"/CN="$SSL_COMMONNAME

TRUSTSTORE_PATH=$OUTPUT_FOLDER/$TRUSTSTORE

set -x #echo on

########CA Certificate
echo "\nGenerating CA Certificate >>>>>> START"

openssl genrsa -out $TEMP_FOLDER/ca_private.key $PRIVATE_KEY_LENGTH 

openssl req -new -key $TEMP_FOLDER/ca_private.key -out $TEMP_FOLDER/ca.csr -subj "$CA_SUBJ"

openssl x509 -req -days $CA_DAYS -in $TEMP_FOLDER/ca.csr -signkey $TEMP_FOLDER/ca_private.key -out $TEMP_FOLDER/ca.crt -extensions v3_ca -extfile $OPENSSL_CONFIG_FILE

openssl rsa -in $TEMP_FOLDER/ca_private.key -text > $TEMP_FOLDER/ca_private.pem

openssl x509 -in $TEMP_FOLDER/ca.crt -out $TEMP_FOLDER/ca_cert.pem

echo "\nGenerating CA Certificate >>>>>> END\n"


########RA Certificate
echo "\nGenerating RA Certificate >>>>>> START"

openssl genrsa -out $TEMP_FOLDER/ra_private.key $PRIVATE_KEY_LENGTH

openssl req -new -key $TEMP_FOLDER/ra_private.key -out $TEMP_FOLDER/ra.csr -subj "$RA_SUBJ"

openssl x509 -req -days $CA_DAYS -in $TEMP_FOLDER/ra.csr -CA $TEMP_FOLDER/ca.crt -CAkey $TEMP_FOLDER/ca_private.key -set_serial $RA_SERIAL -out $TEMP_FOLDER/ra.crt -extensions v3_req -extfile $OPENSSL_CONFIG_FILE

openssl rsa -in $TEMP_FOLDER/ra_private.key -text > $TEMP_FOLDER/ra_private.pem

openssl x509 -in $TEMP_FOLDER/ra.crt -out $TEMP_FOLDER/ra_cert.pem

echo "\nGenerating RA Certificate >>>>>> END \n"


########SSL Certificate
echo "\nGenerating SSL Certificate >>>>>> START"

openssl genrsa -out $TEMP_FOLDER/ia.key $PRIVATE_KEY_LENGTH

openssl req -new -key $TEMP_FOLDER/ia.key -out $TEMP_FOLDER/ia.csr -subj "$SSL_SUBJ"

openssl x509 -req -days $SSL_DAYS -in $TEMP_FOLDER/ia.csr -CA $TEMP_FOLDER/ca_cert.pem -CAkey $TEMP_FOLDER/ca_private.pem -set_serial $SSL_SERIAL -out $TEMP_FOLDER/ia.crt

echo "\nGenerating SSL Certificate >>>>>> END \n"


########PKCS12 files
echo "\nGenerating the PKCS12 files >>>>>> START"

openssl pkcs12 -export -out $TEMP_FOLDER/ia.p12 -inkey $TEMP_FOLDER/ia.key -in $TEMP_FOLDER/ia.crt -CAfile $TEMP_FOLDER/ca_cert.pem -name "$IA_PKCS12_ALIAS" -passout pass:$IA_PKCS12_PASSWORD

openssl pkcs12 -export -out $TEMP_FOLDER/ca.p12 -inkey $TEMP_FOLDER/ca_private.pem -in $TEMP_FOLDER/ca_cert.pem -name "$CA_PKCS12_ALIAS" -passout pass:$CA_PKCS12_PASSWORD

openssl pkcs12 -export -out $TEMP_FOLDER/ra.p12 -inkey $TEMP_FOLDER/ra_private.pem -in $TEMP_FOLDER/ra_cert.pem -chain -CAfile $TEMP_FOLDER/ca_cert.pem -name "$RA_PKCS12_ALIAS" -passout pass:$RA_PKCS12_PASSWORD

echo "\nGenerating the PKCS12 files >>>>>> END"


########Importing the PKCS12 to JKS
echo "\nImporting the PKCS12 to JKS >>>>>> START"

keytool -importkeystore -srckeystore $TEMP_FOLDER/ia.p12 -srcstoretype PKCS12 -destkeystore $OUTPUT_FOLDER/wso2carbon.jks -noprompt -deststorepass $WSO2CARBON -srcstorepass $IA_PKCS12_PASSWORD

keytool -importkeystore -srckeystore $TEMP_FOLDER/ia.p12 -srcstoretype PKCS12 -destkeystore $OUTPUT_FOLDER/client-truststore.jks -noprompt -deststorepass $WSO2CARBON -srcstorepass $IA_PKCS12_PASSWORD

keytool -importkeystore -srckeystore $TEMP_FOLDER/ca.p12 -srcstoretype PKCS12 -destkeystore $OUTPUT_FOLDER/wso2emm.jks -noprompt -deststorepass $WSO2EMM_JKS_PASSWORD -srcstorepass $CA_PKCS12_PASSWORD

keytool -importkeystore -srckeystore $TEMP_FOLDER/ra.p12 -srcstoretype PKCS12 -destkeystore $OUTPUT_FOLDER/wso2emm.jks -noprompt -deststorepass $WSO2EMM_JKS_PASSWORD -srcstorepass $RA_PKCS12_PASSWORD

echo "\nImporting the PKCS12 to JKS >>>>>> END"

########Creating the TrustStore file for Android
echo "\nCreating the TrustStore for Android using the CA Cert"
ALIAS=`openssl x509 -inform PEM -subject_hash -noout -in ./temp/ca_cert.pem`

keytool -noprompt -import -v -trustcacerts -alias $ALIAS \
      -file $TEMP_FOLDER/ca_cert.pem \
      -keystore $TRUSTSTORE_PATH -storetype BKS \
      -providerclass org.bouncycastle.jce.provider.BouncyCastleProvider \
      -providerpath $BKS_CONVERTER \
      -storepass $TRUSTSTORE_PASSWORD

echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PROCESS COMPLETED SUCCESSFULLY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
set +x #echo on
