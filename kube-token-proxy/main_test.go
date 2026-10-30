package main

import (
	"bufio"
	"crypto/tls"
	"crypto/x509"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

const testPrefix = "/.shell/org-cluster"

type apiCall struct {
	path, query, authorization, tokenHeader, impersonate string
}

// newTestProxy starts a fake Kubernetes API behind the proxy.
func newTestProxy(t *testing.T) (*httptest.Server, *[]apiCall) {
	t.Helper()
	calls := &[]apiCall{}
	api := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*calls = append(*calls, apiCall{
			path:          r.URL.Path,
			query:         r.URL.RawQuery,
			authorization: r.Header.Get("Authorization"),
			tokenHeader:   r.Header.Get(TokenHeader),
			impersonate:   r.Header.Get("Impersonate-User"),
		})
		if r.Header.Get("Upgrade") == "" {
			w.WriteHeader(http.StatusOK)
			return
		}
		conn, rw, err := w.(http.Hijacker).Hijack()
		if err != nil {
			t.Error(err)
			return
		}
		defer conn.Close()
		_, _ = io.WriteString(rw, "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: "+r.Header.Get("Upgrade")+"\r\n\r\n")
		_ = rw.Flush()
		line, _ := rw.ReadString('\n')
		_, _ = io.WriteString(rw, "echo:"+line)
		_ = rw.Flush()
	}))
	t.Cleanup(api.Close)
	apiURL, err := url.Parse(api.URL)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(api.Certificate())
	proxy := httptest.NewServer(newHandler(config{
		api:    apiURL,
		prefix: testPrefix,
		tls:    &tls.Config{RootCAs: roots, ServerName: "example.com"},
	}))
	t.Cleanup(proxy.Close)
	return proxy, calls
}

func TestForwardsExecWithTheCallerToken(t *testing.T) {
	proxy, calls := newTestProxy(t)
	req, _ := http.NewRequest(http.MethodPost, proxy.URL+testPrefix+"/api/v1/namespaces/app/pods/php-0/exec?command=sh&tty=true", nil)
	req.Header.Set(TokenHeader, "session-token")
	// FRP clears its Basic credentials to an empty value before forwarding.
	req.Header.Set("Authorization", "")
	req.Header.Set("Impersonate-User", "system:admin")
	req.Header.Set("Impersonate-Group", "system:masters")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || len(*calls) != 1 {
		t.Fatalf("status = %d, API calls = %d", resp.StatusCode, len(*calls))
	}
	got := (*calls)[0]
	if got.path != "/api/v1/namespaces/app/pods/php-0/exec" || got.query != "command=sh&tty=true" {
		t.Fatalf("forwarded %s?%s", got.path, got.query)
	}
	if got.authorization != "Bearer session-token" {
		t.Fatalf("Authorization = %q", got.authorization)
	}
	if got.tokenHeader != "" || got.impersonate != "" {
		t.Fatalf("token header %q or impersonation %q reached the API", got.tokenHeader, got.impersonate)
	}
}

func TestRefusesEverythingExceptExec(t *testing.T) {
	proxy, calls := newTestProxy(t)
	for name, tc := range map[string]struct {
		method, path, token string
		want                int
	}{
		"missing token":  {http.MethodPost, testPrefix + "/api/v1/namespaces/app/pods/php-0/exec", "", http.StatusUnauthorized},
		"pod list":       {http.MethodGet, testPrefix + "/api/v1/namespaces/app/pods", "t", http.StatusNotFound},
		"secrets":        {http.MethodGet, testPrefix + "/api/v1/namespaces/app/secrets/db", "t", http.StatusNotFound},
		"attach":         {http.MethodPost, testPrefix + "/api/v1/namespaces/app/pods/php-0/attach", "t", http.StatusNotFound},
		"version":        {http.MethodGet, testPrefix + "/version", "t", http.StatusNotFound},
		"without prefix": {http.MethodPost, "/api/v1/namespaces/app/pods/php-0/exec", "t", http.StatusNotFound},
		"other cluster":  {http.MethodPost, testPrefix + "2/api/v1/namespaces/app/pods/php-0/exec", "t", http.StatusNotFound},
		"path traversal": {http.MethodPost, testPrefix + "/api/v1/namespaces/app/pods/a/../../../secrets/exec", "t", http.StatusNotFound},
		"dot namespace":  {http.MethodPost, testPrefix + "/api/v1/namespaces/../pods/php-0/exec", "t", http.StatusNotFound},
		"dot pod":        {http.MethodPost, testPrefix + "/api/v1/namespaces/app/pods/../exec", "t", http.StatusNotFound},
		"encoded slash":  {http.MethodPost, testPrefix + "/api/v1/namespaces/app/pods/a%2F..%2Fb/exec", "t", http.StatusNotFound},
		"delete on exec": {http.MethodDelete, testPrefix + "/api/v1/namespaces/app/pods/php-0/exec", "t", http.StatusNotFound},
	} {
		t.Run(name, func(t *testing.T) {
			req, _ := http.NewRequest(tc.method, proxy.URL+tc.path, nil)
			if tc.token != "" {
				req.Header.Set(TokenHeader, tc.token)
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatal(err)
			}
			resp.Body.Close()
			if resp.StatusCode != tc.want {
				t.Fatalf("status = %d, want %d", resp.StatusCode, tc.want)
			}
		})
	}
	if len(*calls) != 0 {
		t.Fatalf("refused requests reached the API: %+v", *calls)
	}
}

func TestUpgradedExecStreamsBothWays(t *testing.T) {
	proxy, calls := newTestProxy(t)
	conn, err := net.Dial("tcp", strings.TrimPrefix(proxy.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_, _ = io.WriteString(conn, "GET "+testPrefix+"/api/v1/namespaces/app/pods/php-0/exec?command=sh HTTP/1.1\r\n"+
		"Host: frps.example.com\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n"+TokenHeader+": session-token\r\n\r\n")
	reader := bufio.NewReader(conn)
	resp, err := http.ReadResponse(reader, nil)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	_, _ = io.WriteString(conn, "hello\n")
	line, err := reader.ReadString('\n')
	if err != nil || line != "echo:hello\n" {
		t.Fatalf("stream returned %q, %v", line, err)
	}
	if got := (*calls)[0].authorization; got != "Bearer session-token" {
		t.Fatalf("Authorization = %q", got)
	}
}
