#!/usr/bin/env bash
# modules/gpgpu.sh — GPGPU 计算栈:OpenCL / ROCm / CUDA(可选,不进任何 profile)
# 读取变量:MY_GPGPU=amd|nvidia|intel;为空则 skip。
# 用法:--extra-modules gpgpu + config 里设 MY_GPGPU。
# 参考:https://wiki.archlinux.org/title/GPGPU
# 与 gpu-amd/gpu-nvidia/gpu-intel 驱动模块独立:不 mod_requires,驱动自行选择
# (headless 计算场景驱动可能来自别处,如容器宿主机)。
# CachyOS 同步 Arch extra 仓库,下列包名两边一致,无需 distro 分支。
# 不装虚拟包 opencl-driver(字母序坑,同 gpu-intel 注释),各 vendor 明确指定 ICD。

mod_install() {
    local gpu=${MY_GPGPU:-}
    [[ -z $gpu ]] && return 0

    # 公共:ICD loader(ocl-icd 是 Arch 选定实现,比各 SDK 自带的新)、
    # clinfo(装完验证平台/设备)、opencl-headers(OpenCL 开发头文件)
    local pkgs=(ocl-icd clinfo opencl-headers)

    case $gpu in
        amd)
            # ROCm:OpenCL 运行时 + HIP 运行时(LLM 推理 ollama/llama.cpp 用 HIP)
            # Polaris(RX 500)及更老卡需环境变量 ROC_ENABLE_PRE_VEGA=1(自行加到
            # environment.d;官方支持列表短,但同代消费卡/APU 实测可用)
            pkgs+=(rocm-opencl-runtime rocm-hip-runtime hip-runtime-amd)
            ;;
        nvidia)
            # opencl-nvidia:官方 OpenCL ICD;cuda:完整 toolkit(nvcc 等,数 GB)
            pkgs+=(opencl-nvidia cuda)
            ;;
        intel)
            # NEO 运行时,OpenCL 3.0 + oneAPI Level Zero;覆盖 Gen12(Rocket/Tiger
            # Lake)核显起及全部 Intel 独显。Gen8/9/11 老核显请自行用 AUR
            # intel-compute-runtime-legacy,不在本模块范围
            pkgs+=(intel-compute-runtime)
            ;;
        *)
            die "MY_GPGPU='$gpu' 无效,可选:amd|nvidia|intel(空=不装)"
            ;;
    esac

    pacman_install "${pkgs[@]}"
}
