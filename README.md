# SAMRAI

SAMRAI (Structured Adaptive Mesh Refinement Application Infrastructure) is an
object-oriented C++ software library that enables exploration of numerical,
algorithmic, parallel computing, and software issues associated with applying
structured adaptive mesh refinement (SAMR) technology in large-scale parallel
application development. SAMRAI provides software tools for developing SAMR
applications that involve coupled physics models, sophisticated numerical
solution methods, and which require high-performance parallel computing
hardware. SAMRAI enables integration of SAMR technology into existing codes and
simplifies the exploration of SAMR methods in new application domains. 

## MI300A Build (Tuolumne / TOSS 4)

### Prerequisites

- ROCm 6.4.0, cray-mpich 8.1.31, CMake 3.29.2 (all available on Tuolumne)

### Build

```bash
./build_samrai_mi300a.sh              # Full build (TPLs + SAMRAI)
./build_samrai_mi300a.sh --tpl-only   # Build only TPLs (CAMP, Umpire, Proteus, RAJA)
./build_samrai_mi300a.sh --samrai-only # Rebuild SAMRAI only (TPLs must exist)
```

This builds CAMP, Umpire, Proteus, and RAJA (JIT branch `feature/bowen/enable-jit`)
into `tpl_build_mi300a/install/`, then builds SAMRAI into `build_mi300a/`.

RAJA is built with JIT support via [Proteus](https://github.com/olympus-HPC/proteus),
which enables runtime specialization of GPU kernels.

### Run

```bash
# Required environment
export LD_LIBRARY_PATH="/usr/tce/packages/cce/cce-17.0.0-magic/cce/x86_64/lib:${LD_LIBRARY_PATH}"
export MPICH_GPU_SUPPORT_ENABLED=1

cd build_mi300a

# Single rank (login node or compute node)
./bin/stencil ../source/test/applications/Stencil/test_inputs/box2d_debug.input

# Multi-rank via flux
flux run -q pdebug -N 1 -n 2 -g 1 ./bin/stencil ../source/test/applications/Stencil/test_inputs/box2d_debug.input
flux run -q pdebug -N 1 -n 4 -g 1 ./bin/stencil ../source/test/applications/Stencil/test_inputs/box2d_adv.input
```

**Environment variables:**
- `LD_LIBRARY_PATH` — Cray runtime libs (needed because cray-mpich depends on CCE runtime)
- `MPICH_GPU_SUPPORT_ENABLED=1` — Enables GPU-aware MPI (required for multi-rank runs)

### Stencil test inputs

| File | Variables | Domain | Steps | Use |
|------|-----------|--------|-------|-----|
| `box2d_debug.input` | 1 | 100x100 | 10 | Quick smoke test |
| `box2d_adv.input` | 20 | 200x200 | 3 | Correctness test |
| `box2d_50_500.input` | 50 | 500x500 | 5 | Medium perf test |
| `box2d_50_1000.input` | 50 | 1000x1000 | 5 | Large perf test |
| `box2d_50_2000.input` | 50 | 2000x2000 | 5 | XL perf test |
| `box3d_2_30.input` | 2 | 30^3 | 10 | Small 3D test |
| `box3d_5_100.input` | 5 | 100^3 | 12 | Large 3D test |

All inputs are in `source/test/applications/Stencil/test_inputs/`.

---

## New Release

The current release is SAMRAI v. 4.0.1.  With the version 4 release, the
SAMRAI project is pleased to introduce new features that support running
applications on GPU-based architectures, using capabilities provided by the
Umpire and RAJA libraries.

## Get Involved

SAMRAI is an open source project, and questions, discussion and contributions
are welcome!

### Mailing List

To get in touch with all the SAMRAI developers, please email samrai@llnl.gov

### Contributions

Contributing to SAMRAI should be easy! We are managing contributions through
pull requents here on GitHub. When you create your pull request, please make
`master` the target branch.

Your PR must pass all of SAMRAI's unit tests, which are enforced using Travis
CI. For information on how to run these tests locally, please see our
[contribution guidelines](CONTRIBUTING.md)

The `master` branch contains the latest development, and releases are tagged.
New features should be created in `feature/<name>`branches and be based on
`master`.

## Citing SAMRAI

We maintain a list of publications
[here](https://computing.llnl.gov/projects/samrai/publications).

## Release

Copyright (c) 1997-2025, Lawrence Livermore National Security, LLC.

Produced at the Lawrence Livermore National Laboratory.

All rights reserved.

Released under LGPL v2.1

For release details and restrictions, please read the LICENSE file. It is also
linked here: [LICENSE](./LICENSE)

`LLNL-CODE-434871`
