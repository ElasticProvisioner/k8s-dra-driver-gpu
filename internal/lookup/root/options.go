/*
Copyright The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package root

import (
	"os"
	"path/filepath"
	"slices"
)

type options struct {
	Root               string
	DevRoot            string
	librarySearchPaths []string
	binarySearchPaths  []string
}

// Option configures a Driver.
type Option func(*options)

// WithDriverRoot sets the root for driver libraries and binaries.
func WithDriverRoot(driverRoot string) Option {
	return func(o *options) {
		o.Root = driverRoot
	}
}

// WithDevRoot sets the root for device nodes.
func WithDevRoot(devRoot string) Option {
	return func(o *options) {
		o.DevRoot = devRoot
	}
}

// WithLibrarySearchPaths sets the driver-library search paths.
func WithLibrarySearchPaths(paths ...string) Option {
	return func(o *options) {
		o.librarySearchPaths = slices.Clone(paths)
	}
}

// WithBinarySearchPaths sets the driver-binary search paths.
func WithBinarySearchPaths(paths ...string) Option {
	return func(o *options) {
		o.binarySearchPaths = slices.Clone(paths)
	}
}

func newOptions(opts ...Option) options {
	o := options{}
	for _, opt := range opts {
		opt(&o)
	}

	if len(o.librarySearchPaths) == 0 {
		o.librarySearchPaths = slices.Clone(defaultLibrarySearchPaths)
	}
	if len(o.binarySearchPaths) == 0 {
		o.binarySearchPaths = slices.Clone(defaultBinarySearchPaths)
	}
	if o.DevRoot == "" {
		o.DevRoot = "/"
		if stat, err := os.Stat(filepath.Join(o.Root, "dev")); err == nil && stat.IsDir() {
			o.DevRoot = o.Root
		}
	}

	return o
}
