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

// Package root provides filesystem discovery helpers for NVIDIA driver
// installations mounted beneath a configurable root.
package root

import (
	"fmt"
	"os"
	"path/filepath"

	"k8s.io/klog/v2"
)

var (
	defaultLibrarySearchPaths = []string{
		"/usr/lib64",
		"/usr/lib/x86_64-linux-gnu",
		"/usr/lib/aarch64-linux-gnu",
		"/lib64",
		"/lib/x86_64-linux-gnu",
		"/lib/aarch64-linux-gnu",
	}
	defaultBinarySearchPaths = []string{
		"/opt/bin",
		"/usr/bin",
		"/usr/sbin",
		"/bin",
		"/sbin",
	}
)

// Driver represents the filesystem roots and search paths for an NVIDIA
// driver installation.
type Driver struct {
	// Root is the root for driver libraries and binaries.
	Root string
	// DevRoot is the root for device nodes.
	DevRoot string

	librarySearchPaths []string
	binarySearchPaths  []string
}

// New creates a Driver using the specified options.
func New(opts ...Option) *Driver {
	options := newOptions(opts...)
	return &Driver{
		Root:               options.Root,
		DevRoot:            options.DevRoot,
		librarySearchPaths: options.librarySearchPaths,
		binarySearchPaths:  options.binarySearchPaths,
	}
}

// DriverLibraryPath returns the path to libnvidia-ml.so.1.
func (r *Driver) DriverLibraryPath() (string, error) {
	return r.FindFile("libnvidia-ml.so.1", r.librarySearchPaths...)
}

// LibraryPath returns the path to a driver library.
func (r *Driver) LibraryPath(name string) (string, error) {
	return r.FindFile(name, r.librarySearchPaths...)
}

// BinaryPath returns the path to a driver binary.
func (r *Driver) BinaryPath(name string) (string, error) {
	return r.FindFile(name, r.binarySearchPaths...)
}

// FindFile searches the root and the provided directories for a regular file.
// Symlinks are resolved before the candidate is returned.
func (r *Driver) FindFile(name string, searchIn ...string) (string, error) {
	for _, dir := range append([]string{"/"}, searchIn...) {
		path := filepath.Join(r.Root, dir, name)
		candidate, err := resolveLink(path)
		if err != nil {
			klog.V(4).Infof("Skipping candidate %q: %v", path, err)
			continue
		}
		info, err := os.Stat(candidate)
		if err != nil {
			klog.V(4).Infof("Skipping candidate %q: %v", candidate, err)
			continue
		}
		if !info.Mode().IsRegular() {
			klog.V(4).Infof("Skipping candidate %q: not a regular file (mode %s)", candidate, info.Mode())
			continue
		}
		return candidate, nil
	}

	return "", fmt.Errorf("error locating %q", name)
}

// resolveLink returns the target of a symlink or the original regular file.
func resolveLink(path string) (string, error) {
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", fmt.Errorf("error resolving link %q: %w", path, err)
	}
	return resolved, nil
}
