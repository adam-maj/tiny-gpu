# tiny-gpu

A minimal GPU implementation in Verilog optimized for learning about how GPUs work from the ground up.

- [Overview]()
- [Architecture]()
- [ISA]()
- [SIMD]()
- [Memory]()
- [Kernels]()
- [Simulation]()

# Overview

If you want to learn how a CPU works all the way from architecture to control signals, there are many resources online to help you.

GPUs are not the same.

Because the GPU market is so competitive, low-level technical details for all modern architectures remain proprietary.

While there are lots of resources to learn about GPU programming, there's almost nothing available to learn about how GPU's work at a hardware level.

The best option is to go through open-source GPU implementations like [Miaow](https://github.com/VerticalResearchGroup/miaow) and [VeriGPU](https://github.com/hughperkins/VeriGPU/tree/main) and try to figure out what's going on. This is challenging since these projects aim at being feature complete and functional, so they're quite complex.

This is why I built `tiny-gpu`!

## What is tiny-gpu?

> [!IMPORTANT]
>
> **tiny-gpu** is a minimal GPU implementation optimized for learning about how GPUs work from the ground up.
>
> Specifically, with the trend toward general-purpose GPUs (GPGPUs) and ML-accelerators like Google's TPU, tiny-gpu focuses on highlighting the general principles of all of these architectures, rather than on the details of graphics-specific hardware.

With this motivation in mind, we can simplify GPUs by cutting out the majority of complexity involved with building a production-grade graphics card, and focus on the core elements that are critical to all of these modern hardwareaccelerators.

This project is primarily focused on exploring:

1. **Architecture** - What does the architecture of a GPU look like? What are the most important elements?
2. **Parallelization** - How is the SIMD progamming model implemented in hardware?
3. **Memory** - How does a GPU work around the constraints of limited memory bandwidth?

For each topic, we'll first cover how tiny-gpu implements the fundamentals. Then, using this as a foundation, we'll explore further optimizations implemented in modern-day GPUs.

# Architecture

<div style="display: grid; grid-template-columns: repeat(2, 1fr);">
  <img src="/docs/images/gpu.png" alt="GPU" style="grid-column: 1 / span 1;"/>
  <img src="/docs/images/core.png" alt="Core" style="grid-column: 2 / span 1;"/>
</div>

![Thread](/docs/images/thread.png)
![ISA](/docs/images/isa.png)
![Key](/docs/images/key.png)
