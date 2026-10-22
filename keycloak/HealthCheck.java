import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.cert.X509Certificate;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

/**
 * Docker healthcheck of Keycloak (whose image has no curl): exits 0 when the URL answers 200. It
 * only ever calls the management interface on localhost, which serves the dev certificate in dev:
 * checking that certificate would prove nothing, so it isn't.
 */
public class HealthCheck {
    public static void main(String[] args) throws Exception {
        TrustManager[] trustAll = { new X509TrustManager() {
            public void checkClientTrusted(X509Certificate[] chain, String authType) {}
            public void checkServerTrusted(X509Certificate[] chain, String authType) {}
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
        } };
        SSLContext ssl = SSLContext.getInstance("TLS");
        ssl.init(null, trustAll, null);
        HttpClient client = HttpClient.newBuilder().sslContext(ssl).build();
        HttpResponse<Void> response = client.send(HttpRequest.newBuilder(URI.create(args[0])).build(),
                HttpResponse.BodyHandlers.discarding());
        System.exit(response.statusCode() == 200 ? 0 : 1);
    }
}
