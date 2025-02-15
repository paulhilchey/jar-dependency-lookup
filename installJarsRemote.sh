#!/bin/bash
# This script will deply all jar files in the WEB-INF/lib directory of an IdentityIQ release
# to the Nexus repository using the mvn deploy command.

# This is a modification of installJarsLocally.sh

# Original Author: Indranil Chakraborty (indranil.chakraborty@sailpoint.com)
# Version: 0.1
# Date: 30-Jun-2020

# Modified: Paul Hilchey (paulh@uvic.ca)
# Date: 14-Feb-2025
# Use JarDependencyLookup-2.0.jar

# Usage:
# 1. Set the values for the below properties
# 2. Ensure that the execution environment has Maven installed and configured to write to the target repository
# 3. Execute script

# Note that the environment on which this script is run must have Maven installed and on the path

# The version of IdentityIQ; this is used to determine which zip file to extract and is used as a namespace separator
export IIQ_BASE_VERSION=8.4
export IIQ_PATCH_VERSION=8.4p2
# The base directory in which the IdentityIQ zip files are present
export BASE_SOFTWARE_PATH=


# An enterprise Nexus repository:
# the repository id, as defined in your maven settings.xml
export REPOSITORY_ID=<repoId>
# the repository url
export REPOSITORY_URL=https://<hostname>/repository/<repoName>
# the repository search endpoint
export REPOSITORY_SEARCH_URL='https://<hostName>/service/rest/v1/search/assets?repository=<repoName>'


### DO NOT CHANGE ANYTHING BELOW THIS LINE
# ****************************************
# A working directory into which content is extracted; this is cleaned up later
export WORK_DIR=$BASE_SOFTWARE_PATH/iiqlibs
# Below are calculated from earlier values
export IIQ_ZIP_FILE=$BASE_SOFTWARE_PATH/identityiq-${IIQ_BASE_VERSION}.zip
export IIQ_PATCH_FILE=$BASE_SOFTWARE_PATH/identityiq-${IIQ_PATCH_VERSION}.jar
export ACCELERATOR_PACK_FILE=$BASE_SOFTWARE_PATH/Accelerator_Pack-${ACCELERATOR_PACK_PATCH_VERSION}.zip

# Check to see if patch file exists and set the effective IIQ version
if [ -f $IIQ_PATCH_FILE ]; then
  export IIQ_VERSION=$IIQ_PATCH_VERSION
else
  export IIQ_VERSION=$IIQ_BASE_VERSION
fi

#
# If a particular IIQ version contains any efix, the efix archives must be stored under the directory following the naming
# convention $BASE_SOFTWARE_PATH/efix/<version><patchlevel>. Each efix archive should be save under a sub-directory
# with the name starting with "efix" and ending with a number (1, 2, 3 .. n etc.).
# This is because efix is accumulative and the later version of efix may override the same file from the earlier version,
# and therefore it is important that efix archivers are processed in proper sequence.
#  The following is an example of efix folder structure for IIQ 8.0p1:
#     $BASE_SOFTWARE_PATH/efix/8.0p1/efix1/identityiq-8.0p1-iiqetn8680.zip
#     $BASE_SOFTWARE_PATH/efix/8.0p1/efix2/identityiq-8.0p1-IIQSAW-2905.zip
#
export EFIX_PATH=$BASE_SOFTWARE_PATH/efix/$IIQ_VERSION
echo "The efix files location for this IIQ verison/patch ($IIQ_VERSION): $EFIX_PATH"

# IIQ Version with efix. If a particular IIQ version contains any efix, 2 versions of iiq war will be installed. One with efix and another one without efix
# The version with efix will follow the naming convention "<version><patchlevel>-efix<number>". The <number> is the higest number representing the latest efix.
export IIQ_VERSION_WITH_EFIX

export APPLY_EFIX=false

# Check if there is any efix for this IIQ Version (Patch)
if [ -d $EFIX_PATH ]; then
  if find $EFIX_PATH/* -maxdepth 0 -type d | read
    then export APPLY_EFIX=true
  fi
fi

export CURRENT_LOC=$PWD

# Create the TMP_DIR, WORK_DIR
rm -rf $WORK_DIR && mkdir $WORK_DIR

# Extract to the WORK_DIR
if [ -f $IIQ_ZIP_FILE ]; then
  echo "Extracting identityiq.war from IIQ base GA"
  unzip -q -d $WORK_DIR/$IIQ_VERSION $IIQ_ZIP_FILE identityiq.war

  echo "Extracting the identity.war file"
  unzip -q -d $WORK_DIR/$IIQ_VERSION/identityiq $WORK_DIR/$IIQ_VERSION/identityiq.war
  echo "Renaming the identityiq.war file"
  mv $WORK_DIR/$IIQ_VERSION/identityiq.war $WORK_DIR/$IIQ_VERSION/iiq-webapp.war

  echo "Is efix required? $APPLY_EFIX"
  if [ -f $IIQ_PATCH_FILE ] || [ $APPLY_EFIX = "true" ]; then
  if [ -f $IIQ_PATCH_FILE ]; then
    echo "Overlaying patch file contents"
    unzip -qo -d $WORK_DIR/$IIQ_VERSION/identityiq $IIQ_PATCH_FILE
    echo "Creating updated iiq-webapp.war"
    cd $WORK_DIR/$IIQ_VERSION/identityiq && zip -r -q $WORK_DIR/$IIQ_VERSION/iiq-webapp.war .
    fi
    if [ $APPLY_EFIX = "true" ]; then
      # Apply efix here if there is any
      echo "Applying efix"
      find $EFIX_PATH -maxdepth 1 -mindepth 1 -type d | sort -n | while read efixDir; do
        echo "Overlaying efix file contents from directory: $efixDir"
        # store iiq efix version into a temp text file during the loop
        echo $IIQ_VERSION-`basename "$efixDir"` > $WORK_DIR/iiq-efix-version.txt
        for efixFile in $efixDir/*; do
          echo "Overlaying efix file contents from file: $efixFile"
          unzip -qo -d $WORK_DIR/$IIQ_VERSION/identityiq $efixFile
        done
      done
      # Read iiq efix version saved the temp text
      export IIQ_VERSION_WITH_EFIX=`cat $WORK_DIR/iiq-efix-version.txt`
      echo "Creating updated iiq-webapp.war with efix"
      echo "IIQ Version with efix: $IIQ_VERSION_WITH_EFIX"
      cd $WORK_DIR/$IIQ_VERSION/identityiq && zip -r -q $WORK_DIR/$IIQ_VERSION/iiq-webapp-efix.war .
    fi

  else
    echo "No patch file found; skipping patch overlay!"
  fi
else
  echo "No base GA file found; script will now terminate!"
  exit 1
fi

cd $CURRENT_LOC
# Upload each file in WEB-INF/lib to the repository
for filename in $WORK_DIR/$IIQ_VERSION/identityiq/WEB-INF/lib/*.jar; do
    fname=`basename $filename .jar`
    jarInfo=$(java -jar JarDependencyLookup-2.0.jar $filename $IIQ_VERSION "$REPOSITORY_SEARCH_URL")
    declare -a strarr="(${jarInfo//,/ })"
    groupId=${strarr[0]}
    artifactId=${strarr[1]}
    version=${strarr[2]}
    repo=${strarr[3]}
    if [ "$repo" != "nexus" ]; then
       mvn deploy:deploy-file -DgroupId=$groupId -DartifactId=$artifactId -Dversion=$version -Dpackaging=jar -Dfile=$filename -DrepositoryId=$REPOSITORY_ID -Durl=$REPOSITORY_URL
    fi
done

# Add the identityiq.war file as a dependency for war file builds
 mvn deploy:deploy-file -DgroupId=sailpoint -DartifactId=iiq-webapp -Dversion=$IIQ_VERSION -Dpackaging=war -Dfile=$WORK_DIR/$IIQ_VERSION/iiq-webapp.war -DrepositoryId=$REPOSITORY_ID -Durl=$REPOSITORY_URL

# Install version of identityiq.war with efix if available
if [ $APPLY_EFIX = "true" ]; then
  mvn deploy:deploy-file -DgroupId=sailpoint -DartifactId=iiq-webapp -Dversion=$IIQ_VERSION_WITH_EFIX -Dpackaging=war -Dfile=$WORK_DIR/$IIQ_VERSION/iiq-webapp-efix.war -DrepositoryId=$REPOSITORY_ID -Durl=$REPOSITORY_URL
fi

# Upload the AP zip file to the repo
if [ -f $ACCELERATOR_PACK_FILE ]; then
  echo "Upload the AP zip file to the repo"
  mvn deploy:deploy-file -DgroupId=sailpoint -DartifactId=Accelerator-Pack -Dversion=$ACCELERATOR_PACK_PATCH_VERSION -Dpackaging=zip -Dfile=$ACCELERATOR_PACK_FILE -DrepositoryId=$REPOSITORY_ID -Durl=$REPOSITORY_URL
else
  echo "No Accelerator Patch file found; skipping uploading!"
fi

# Create a BOM file, the quick and dirty way
java -jar JarDependencyLookup-2.0.jar $WORK_DIR/$IIQ_VERSION/identityiq/WEB-INF/lib $IIQ_VERSION "$REPOSITORY_SEARCH_URL" > $WORK_DIR/$IIQ_VERSION/pom.temp

# Pretty print and store the output
cat $WORK_DIR/$IIQ_VERSION/pom.temp | tee $WORK_DIR/$IIQ_VERSION/pom.xml

# Upload the BOM pom.xml to the repo
mvn deploy:deploy-file -DgroupId=sailpoint -DartifactId=iiq-bom -Dversion=$IIQ_VERSION -Dpackaging=pom -Dfile=$WORK_DIR/$IIQ_VERSION/pom.xml -DrepositoryId=$REPOSITORY_ID -Durl=$REPOSITORY_URL

if [ $APPLY_EFIX = "true" ]; then
mvn deploy:deploy-file -DgroupId=sailpoint -DartifactId=iiq-bom -Dversion=$IIQ_VERSION_WITH_EFIX -Dpackaging=pom -Dfile=$WORK_DIR/$IIQ_VERSION/pom.xml -DrepositoryId=$REPOSITORY_ID -Durl=$REPOSITORY_URL
fi

# Cleanup
rm -rf $WORK_DIR
