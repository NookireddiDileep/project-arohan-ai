#!/usr/bin/env python3
"""Offline roofline calculator for AI-01. Standard library only.

All GPU numbers are inputs you can change. The defaults are rounded
values from public NVIDIA documents (see the note's Sources). Results
are upper bounds from a first-order model, not benchmark results.
"""
import argparse


def main() -> None:
    p = argparse.ArgumentParser(description="Roofline and decode-bound estimate")
    p.add_argument("--tflops", type=float, default=312.0,
                   help="dense FP16 Tensor TFLOPS (A100 default)")
    p.add_argument("--bw-gbs", type=float, default=2039.0,
                   help="HBM bandwidth in GB/s (A100 80GB default)")
    p.add_argument("--params-b", type=float, default=8.0,
                   help="model parameters in billions")
    p.add_argument("--bytes-per-param", type=float, default=2.0,
                   help="2 = FP16/BF16, 1 = FP8/INT8, 0.5 = 4-bit")
    args = p.parse_args()

    ops_per_byte = (args.tflops * 1e12) / (args.bw_gbs * 1e9)
    weights_gb = args.params_b * args.bytes_per_param
    print(f"GPU ops:byte ratio      : {ops_per_byte:.0f} FLOP per byte")
    print(f"Weights in memory       : {weights_gb:.1f} GB")
    print()
    print("batch  intensity(FLOP/B)  regime          decode tokens/s per sequence (upper bound)")
    for batch in (1, 4, 16, 64, 256, 1024):
        # Per decode step, each weight is read once and used for 2 FLOPs per sequence.
        intensity = 2.0 * batch / args.bytes_per_param
        regime = "memory-bound" if intensity < ops_per_byte else "compute-bound"
        step_s_mem = (weights_gb * 1e9) / (args.bw_gbs * 1e9)
        step_s_math = (2.0 * args.params_b * 1e9 * batch) / (args.tflops * 1e12)
        step_s = max(step_s_mem, step_s_math)
        print(f"{batch:5d}  {intensity:17.1f}  {regime:14s}  {1.0 / step_s:10.1f}")
    print()
    print("Ignores KV-cache reads, attention, kernel overheads and communication.")


if __name__ == "__main__":
    main()
