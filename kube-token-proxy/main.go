// Command kube-token-proxy forwards Kubernetes exec requests to the cluster API
// with a token supplied by the caller.
//
// It exists because a single request cannot carry two Authorization headers:
// FRP's HTTP Basic auth uses that header at the edge, and the Kubernetes API
// needs a bearer token. The caller sends the token in a separate header, and
// this proxy moves it. The proxy holds no credentials of its own, so a caller
// can only do what its own token allows, and only pod exec is reachable.
package main

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

const (
	// TokenHeader carries the caller's Kubernetes token.
	TokenHeader = "X-Wodby-Kube-Token"

	defaultListen = "127.0.0.1:8002"
	defaultAPI    = "https://kubernetes.default.svc"
	defaultCAFile = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
)

// execPath matches only pod exec, with valid Kubernetes names, so a path such as
// ".." can never reach another API resource.
var execPath = regexp.MustCompile(`^/api/v1/namespaces/[a-z0-9]([a-z0-9-]*[a-z0-9])?/pods/[a-z0-9]([a-z0-9.-]*[a-z0-9])?/exec$`)

type config struct {
	api    *url.URL
	prefix string
	tls    *tls.Config
}

func newHandler(cfg config) http.Handler {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.TLSClientConfig = cfg.tls
	// Exec upgrades its connection, which requires HTTP/1.1.
	transport.ForceAttemptHTTP2 = false

	proxy := &httputil.ReverseProxy{
		Transport:     transport,
		FlushInterval: -1,
		Rewrite: func(r *httputil.ProxyRequest) {
			token := r.In.Header.Get(TokenHeader)
			r.SetURL(cfg.api)
			r.Out.URL.Path = strings.TrimPrefix(r.In.URL.Path, cfg.prefix)
			r.Out.URL.RawPath = ""
			r.Out.Header.Del(TokenHeader)
			for name := range r.Out.Header {
				// The token alone decides what the request may do.
				if strings.HasPrefix(name, "Impersonate-") {
					r.Out.Header.Del(name)
				}
			}
			r.Out.Header.Set("Authorization", "Bearer "+token)
		},
		ErrorHandler: func(w http.ResponseWriter, _ *http.Request, err error) {
			log.Printf("kubernetes API request failed: %s", err)
			http.Error(w, "kubernetes API unavailable", http.StatusBadGateway)
		},
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path, ok := strings.CutPrefix(r.URL.Path, cfg.prefix)
		if !ok || !execPath.MatchString(path) || (r.Method != http.MethodGet && r.Method != http.MethodPost) {
			http.NotFound(w, r)
			return
		}
		if r.Header.Get(TokenHeader) == "" {
			http.Error(w, "missing token", http.StatusUnauthorized)
			return
		}
		proxy.ServeHTTP(w, r)
	})
}

func loadConfig() (config, error) {
	api, err := url.Parse(envOr("KUBE_TOKEN_PROXY_API", defaultAPI))
	if err != nil || api.Scheme != "https" || api.Host == "" {
		return config{}, errors.New("KUBE_TOKEN_PROXY_API must be an https URL")
	}
	prefix := strings.TrimSuffix(os.Getenv("KUBE_TOKEN_PROXY_PREFIX"), "/")
	if prefix == "" {
		return config{}, errors.New("KUBE_TOKEN_PROXY_PREFIX is required")
	}
	caFile := envOr("KUBE_TOKEN_PROXY_CA_FILE", defaultCAFile)
	ca, err := os.ReadFile(caFile)
	if err != nil {
		return config{}, fmt.Errorf("reading the cluster CA: %w", err)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(ca) {
		return config{}, fmt.Errorf("no certificates in %s", caFile)
	}
	return config{api: api, prefix: prefix, tls: &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}}, nil
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{
		Addr:              envOr("KUBE_TOKEN_PROXY_LISTEN", defaultListen),
		Handler:           newHandler(cfg),
		ReadHeaderTimeout: 30 * time.Second,
	}
	log.Fatal(server.ListenAndServe())
}
