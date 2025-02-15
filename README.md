# jar-dependency-lookup
Utility for use with the SailPoint Dev-Sec-Ops toolkit

This replaces the JarDependencyLookup-1.0.jar included with the DevSecOps toolkit.
Improvements:
 - when searching the Maven Central repository, the URL is correctly formatted
 - can optionally search an enterprise Nexus repository, in addition to central

To use, unpack in your DevSecOps toolkit. Then, modify installJarsLocally.sh,
replacing references to JarDependencyLookup-1.0.jar with JarDependencyLookup-2.0.jar.

If you want to deploy artifacts into an enterprise Nexus repository, use the installJarsRemote.sh.
