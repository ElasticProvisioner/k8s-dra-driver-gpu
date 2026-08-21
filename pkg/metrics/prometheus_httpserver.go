/*
Copyright The Kubernetes Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package metrics

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"path"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"k8s.io/component-base/metrics/legacyregistry"
	"k8s.io/klog/v2"
)

// NewLegacyPrometheusHandler returns an HTTP handler that gathers metrics from
// k8s.io/component-base/metrics/legacyregistry together with instrumentation
// for the scrape itself (same pattern as Kubernetes component-base metrics).
func NewLegacyPrometheusHandler() http.Handler {
	reg := prometheus.NewRegistry()
	gatherers := prometheus.Gatherers{
		// Go runtime and process metrics, etc.:
		// https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/component-base/metrics/legacyregistry/registry.go
		legacyregistry.DefaultGatherer,
	}
	gatherers = append(gatherers, reg)
	return promhttp.InstrumentMetricHandler(
		reg,
		promhttp.HandlerFor(gatherers, promhttp.HandlerOpts{}))
}

// RunPrometheusMetricsServer listens on endpoint and serves Prometheus
// metrics until ctx is canceled.
func RunPrometheusMetricsServer(ctx context.Context, endpoint, metricsPath string) error {
	if metricsPath == "" {
		return nil
	}
	if endpoint == "" {
		return fmt.Errorf("metrics endpoint is required when metrics path is set")
	}

	mux := http.NewServeMux()
	actualPath := path.Join("/", metricsPath)
	mux.Handle(actualPath, NewLegacyPrometheusHandler())

	listener, err := net.Listen("tcp", endpoint)
	if err != nil {
		return fmt.Errorf("listen on metrics endpoint: %w", err)
	}

	server := &http.Server{Handler: mux}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	go func() {
		klog.InfoS("Starting metrics HTTP server", "endpoint", endpoint, "path", actualPath)
		err := server.Serve(listener)
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			klog.ErrorS(err, "metrics HTTP server failed", "endpoint", endpoint, "path", actualPath)
			klog.FlushAndExit(klog.ExitFlushTimeout, 1)
		}
	}()

	return nil
}
