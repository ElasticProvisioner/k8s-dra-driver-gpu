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
	"testing"

	"github.com/stretchr/testify/require"
)

func TestFindFile(t *testing.T) {
	testRoot := t.TempDir()
	target := filepath.Join(testRoot, "opt", "libnvidia-ml.so.1")
	require.NoError(t, os.MkdirAll(filepath.Dir(target), 0o755))
	require.NoError(t, os.WriteFile(target, nil, 0o644))

	linkDir := filepath.Join(testRoot, "usr", "lib64")
	require.NoError(t, os.MkdirAll(linkDir, 0o755))
	require.NoError(t, os.Symlink(target, filepath.Join(linkDir, filepath.Base(target))))

	found, err := New(WithDriverRoot(testRoot)).FindFile(filepath.Base(target), "/usr/lib64")
	require.NoError(t, err)
	want, err := filepath.EvalSymlinks(target)
	require.NoError(t, err)
	require.Equal(t, want, found)
}

func TestFindFileSkipsNonRegularCandidates(t *testing.T) {
	testRoot := t.TempDir()
	name := "libnvidia-ml.so.1"
	require.NoError(t, os.MkdirAll(filepath.Join(testRoot, "usr", "lib64", name), 0o755))

	target := filepath.Join(testRoot, "usr", "lib", name)
	require.NoError(t, os.MkdirAll(filepath.Dir(target), 0o755))
	require.NoError(t, os.WriteFile(target, nil, 0o644))

	found, err := New(WithDriverRoot(testRoot)).FindFile(name, "/usr/lib64", "/usr/lib")
	require.NoError(t, err)
	want, err := filepath.EvalSymlinks(target)
	require.NoError(t, err)
	require.Equal(t, want, found)
}

func TestFindFileRejectsInvalidCandidates(t *testing.T) {
	const name = "libnvidia-ml.so.1"

	tests := map[string]func(*testing.T, string){
		"directory": func(t *testing.T, testRoot string) {
			require.NoError(t, os.MkdirAll(filepath.Join(testRoot, "usr", "lib64", name), 0o755))
		},
		"symlink to directory": func(t *testing.T, testRoot string) {
			target := filepath.Join(testRoot, "opt", name)
			require.NoError(t, os.MkdirAll(target, 0o755))
			linkDir := filepath.Join(testRoot, "usr", "lib64")
			require.NoError(t, os.MkdirAll(linkDir, 0o755))
			require.NoError(t, os.Symlink(target, filepath.Join(linkDir, name)))
		},
		"dangling symlink": func(t *testing.T, testRoot string) {
			linkDir := filepath.Join(testRoot, "usr", "lib64")
			require.NoError(t, os.MkdirAll(linkDir, 0o755))
			require.NoError(t, os.Symlink(filepath.Join(testRoot, "missing.so"), filepath.Join(linkDir, name)))
		},
		"missing": func(t *testing.T, _ string) {},
	}

	for description, setup := range tests {
		t.Run(description, func(t *testing.T) {
			testRoot := t.TempDir()
			setup(t, testRoot)

			_, err := New(WithDriverRoot(testRoot)).FindFile(name, "/usr/lib64")
			require.Error(t, err)
		})
	}
}

func TestRootPaths(t *testing.T) {
	testRoot := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(testRoot, "dev"), 0o755))

	writeFile := func(relativePath string) string {
		path := filepath.Join(testRoot, relativePath)
		require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
		require.NoError(t, os.WriteFile(path, nil, 0o644))
		resolved, err := filepath.EvalSymlinks(path)
		require.NoError(t, err)
		return resolved
	}

	wantNVML := writeFile("usr/lib64/libnvidia-ml.so.1")
	wantFM := writeFile("usr/lib64/libnvfm.so")
	wantSMI := writeFile("usr/bin/nvidia-smi")

	r := New(WithDriverRoot(testRoot))
	require.Equal(t, testRoot, r.DevRoot)

	got, err := r.DriverLibraryPath()
	require.NoError(t, err)
	require.Equal(t, wantNVML, got)

	got, err = r.LibraryPath("libnvfm.so")
	require.NoError(t, err)
	require.Equal(t, wantFM, got)

	got, err = r.BinaryPath("nvidia-smi")
	require.NoError(t, err)
	require.Equal(t, wantSMI, got)

	require.Equal(t, "/", New(WithDriverRoot(t.TempDir())).DevRoot)

	devIsFile := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(devIsFile, "dev"), nil, 0o644))
	require.Equal(t, "/", New(WithDriverRoot(devIsFile)).DevRoot)
}

func TestOptions(t *testing.T) {
	testRoot := t.TempDir()
	customDevRoot := t.TempDir()
	library := filepath.Join(testRoot, "custom-lib", "libnvidia-ml.so.1")
	binary := filepath.Join(testRoot, "custom-bin", "nvidia-smi")
	require.NoError(t, os.MkdirAll(filepath.Dir(library), 0o755))
	require.NoError(t, os.MkdirAll(filepath.Dir(binary), 0o755))
	require.NoError(t, os.WriteFile(library, nil, 0o644))
	require.NoError(t, os.WriteFile(binary, nil, 0o755))

	r := New(
		WithDriverRoot(testRoot),
		WithDevRoot(customDevRoot),
		WithLibrarySearchPaths("/custom-lib"),
		WithBinarySearchPaths("/custom-bin"),
	)
	require.Equal(t, testRoot, r.Root)
	require.Equal(t, customDevRoot, r.DevRoot)

	got, err := r.DriverLibraryPath()
	require.NoError(t, err)
	want, err := filepath.EvalSymlinks(library)
	require.NoError(t, err)
	require.Equal(t, want, got)

	got, err = r.BinaryPath("nvidia-smi")
	require.NoError(t, err)
	want, err = filepath.EvalSymlinks(binary)
	require.NoError(t, err)
	require.Equal(t, want, got)
}
