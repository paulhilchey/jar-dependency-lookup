package ca.uvic.idam.iiq;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.math.BigInteger;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.MessageFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

public class JarDependencyLookup {
    public static void main(String[] args) throws IOException {
        String path = args[0];
        String iiqVersion = args[1];
        String repoUrl = null;
        if (args.length >= 3 && args[2].length() > 0) {
          repoUrl = args[2];     // https://.../service/rest/v1/search/assets?repository=...
        }

        File inputFile = new File(path);

        if (inputFile.isFile()) {
            // Get info for an individual jar file, for use by mvn deploy:deploy-file
            Info info = getJarInfo(path, iiqVersion, repoUrl);
            System.out.println(MessageFormat.format("{0},{1},{2},{3}", info.groupId, info.artifactId, info.version, info.repo));
        } else if (inputFile.isDirectory()) {
            // Generate a BOM pom

            // Fetch the dependency info for the jar files
            List<Info> infos = new ArrayList<>();
            for (File file : inputFile.listFiles()) {
              if (file.getName().toLowerCase().endsWith(".jar")) {
                infos.add(getJarInfo(file.getPath(), iiqVersion, repoUrl));
              }
            }

            Collections.sort(infos);

            // Start building the pom
            StringBuilder dependencies = new StringBuilder();
            dependencies.append(MessageFormat.format(
               "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
               "<project xmlns=\"http://maven.apache.org/POM/4.0.0\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"" +
               " xsi:schemaLocation=\"http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd\">\n" +
               "<modelVersion>4.0.0</modelVersion>\n" +
               "<groupId>sailpoint</groupId>\n" +
               "<artifactId>iiq-bom</artifactId>\n" +
               "<version>{0}</version>\n" +
               "<packaging>pom</packaging>\n<name>IIQ BOM</name>\n" +
               "<description>IdentityIQ Bill of Material</description>\n" +
               "<dependencies>\n",
               iiqVersion));

            // Add jar file dependencies to the pom
            for (Info info : infos) {
                dependencies.append("<dependency>\n");
                if (info.groupId != null)
                  dependencies.append(MessageFormat.format(" <groupId>{0}</groupId>\n", info.groupId));
                dependencies.append(MessageFormat.format(" <artifactId>{0}</artifactId>\n", info.artifactId));
                dependencies.append(MessageFormat.format(" <version>{0}</version>\n", info.version));
                dependencies.append(" <type>jar</type>\n");
                dependencies.append("</dependency>\n");
            }

            // Add dependency on iiq-webapp to the pom
            dependencies.append(MessageFormat.format("<dependency>\n <groupId>sailpoint</groupId>\n <artifactId>iiq-webapp</artifactId>\n <type>war</type>\n <version>{0}</version>\n</dependency>\n", iiqVersion));

            // Complete the pom and output
            dependencies.append("</dependencies>\n</project>");
            System.out.println(dependencies);
        }
    }

    static Info getJarInfo(String path, String defaultVersion, String repoUrl) throws IOException {
      File file = new File(path);
      String sha1sum = sha1(file);

      Info nexusInfo = null;

      if (repoUrl != null) {
        nexusInfo = getInfoFromNexus(sha1sum, repoUrl);
        if (nexusInfo != null && ! nexusInfo.groupId.equals("sailpoint"))
          return nexusInfo;
      }

      Info centralInfo = getInfoFromCentral(sha1sum);
      if (centralInfo != null) {
        return centralInfo;
      }

      if (nexusInfo != null)
        return nexusInfo;
      return new Info("", "sailpoint", file.getName(), defaultVersion);
    }

        
    static Info getInfoFromCentral(String sha1sum) throws IOException {
      String query = "https://search.maven.org/solrsearch/select?q=1:" + sha1sum + "&wt=json";
       URL url = new URL(query);
       HttpURLConnection connection = (HttpURLConnection)url.openConnection();
       try {
        int responseCode = connection.getResponseCode();
        if (responseCode == 404) {
          return null;
        }
        if (responseCode != 200) {
          throw new IOException();
        }
       
        InputStream is = connection.getInputStream();
        JsonNode node = objectMapper.readTree(is);
        is.close();

        JsonNode doc = node.path("response").path("docs").path(0);
        String groupId = doc.path("g").asText(null);
        String artifactId = doc.path("a").asText(null);
        String version = doc.path("v").asText(null);

        if (artifactId == null || version == null)
          return null;

        return new Info("central", groupId, artifactId, version);
       }
       finally {
         connection.disconnect();
       }
   }

   static Info getInfoFromNexus(String sha1sum, String repoUrl) throws IOException {
      String query = repoUrl + "&sha1=" + sha1sum;
      URL url = new URL(query);
      HttpURLConnection connection = (HttpURLConnection)url.openConnection();
      try {
        int responseCode = connection.getResponseCode();
        if (responseCode == 404) {
          return null;
        }
        if (responseCode != 200) {
          throw new IOException();
        }

        InputStream is = connection.getInputStream();
        JsonNode node = objectMapper.readTree(is);
        is.close();

        Info bestInfo = null;

        // If multiple artifacts match, favour the non-sailpoint group
        JsonNode items = node.path("items");
        for (JsonNode item : items) {
          JsonNode maven2 = item.path("maven2");
          String groupId = maven2.path("groupId").asText(null);
          String artifactId = maven2.path("artifactId").asText(null);
          String version = maven2.path("version").asText(null);
          if (artifactId == null || version == null)
            continue;
          if (bestInfo == null || bestInfo.groupId.equals("sailpoint")) {
            bestInfo = new Info("nexus", groupId, artifactId, version);
          }
        }

        // System.out.println("getInfoFromNexus: " + bestInfo.groupId + " " + bestInfo.artifactId + " " + bestInfo.version);
        return bestInfo;
       }
       finally {
         connection.disconnect();
       }
   }


    static String sha1(File file) throws IOException {
      MessageDigest md;
      try {
        md = MessageDigest.getInstance("SHA-1");
      }
      catch (NoSuchAlgorithmException e) {
        throw new RuntimeException("NoSuchAlgorithmException");
      }
      DigestInputStream dis = new DigestInputStream(new FileInputStream(file), md);
      byte[] buffer = new byte[65536];
      while (dis.read(buffer, 0, 65536) != -1)
        ;
      dis.close();
      return String.format("%040x", new BigInteger(1, md.digest()));
    }

    static class Info implements Comparable<Info> {
      String repo;
      String groupId;
      String artifactId;
      String version;
      Comparator<String> comparator = Comparator.nullsLast(Comparator.naturalOrder());

      public Info(String repo, String groupId, String artifactId, String version) {
        this.repo = repo;
        this.groupId = groupId;
        this.artifactId = artifactId;
        this.version = version;
      }
      public boolean equals(Info info) {
        return Objects.equals(this.repo, info.repo) &&
               Objects.equals(this.groupId, info.groupId) &&
               Objects.equals(this.artifactId, info.artifactId) &&
               Objects.equals(this.version, info.version);
      }
      @Override
      public int compareTo(Info info) {
        if (this == info)
          return 0;
        int i;
        if ((i = Objects.compare(this.groupId, info.groupId, comparator)) != 0)
          return i;
        if ((i = Objects.compare(this.artifactId, info.artifactId, comparator)) != 0)
          return i;
        if ((i = Objects.compare(this.version, info.version, comparator)) != 0)
          return i;
        if ((i = Objects.compare(this.repo, info.repo, comparator)) != 0)
          return i;
        return 0;
      }
    }

    static ObjectMapper objectMapper = new ObjectMapper();
}

