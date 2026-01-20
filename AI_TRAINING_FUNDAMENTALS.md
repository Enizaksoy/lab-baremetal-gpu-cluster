# AI Training Fundamentals & NCCL Guide

## The Big Picture: Teaching a Machine

AI training is like teaching a student using examples:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         AI TRAINING = LEARNING FROM EXAMPLES                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   DATASET (Your Textbook)                                                       │
│   ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐            │
│   │ Cat │ │ Dog │ │ Cat │ │ Dog │ │ Cat │ │ Dog │ │ Cat │ │ Dog │            │
│   └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘            │
│                                                                                 │
│   1,000,000 images with labels                                                  │
│                                                                                 │
│   MODEL (The Student's Brain)                                                   │
│   Learns patterns: "Cats have pointy ears, dogs have floppy ears..."           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Terms Explained

### 1. BATCH / ITERATION

**One iteration = Process a small group of images**

```
Dataset: 1,000,000 images
Batch Size: 32 images

ONE ITERATION = Process 32 images at once

WHY BATCHES?
• 1 image at a time = too slow
• All 1M images at once = won't fit in GPU memory (16GB)
• 32 images = good balance of speed and memory
```

### 2. EPOCH

**One epoch = Going through ALL images once**

```
Dataset: 1,000,000 images
Batch Size: 32
Iterations per Epoch: 1,000,000 ÷ 32 = 31,250 iterations

ONE EPOCH = See every image exactly once

TYPICAL TRAINING: 10-100 EPOCHS
(Like a student reading the textbook 10-100 times!)
```

| Term | Formula | Example |
|------|---------|---------|
| Iterations per Epoch | Dataset Size ÷ Batch Size | 1,000,000 ÷ 32 = 31,250 |
| Total Iterations | Iterations × Epochs | 31,250 × 100 = 3,125,000 |

### 3. GRADIENT

**Gradient = "How wrong was I, and how do I fix it?"**

```
STEP 1: Model makes a prediction
   Input: Cat image
   Model thinks: "70% Dog, 30% Cat"  ❌ WRONG!

STEP 2: Calculate ERROR (Loss)
   Correct answer:   100% Cat, 0% Dog
   Model's answer:   30% Cat, 70% Dog
   Error (Loss):     Pretty bad! (0.7)

STEP 3: Calculate GRADIENT
   Gradient = "Which direction should I adjust to be LESS wrong?"

   Like a GPS: "Go 0.1 North, 0.2 East" to reach destination
```

---

## How AI Knows the Correct Answer: LABELED DATA

**Humans tell it the correct answer FIRST!**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         LABELED TRAINING DATA                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   BEFORE TRAINING: Humans label every image                                     │
│                                                                                 │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐        │
│   │   Image 1   │   │   Image 2   │   │   Image 3   │   │   Image 4   │        │
│   │   (cat)     │   │   (dog)     │   │   (cat)     │   │   (dog)     │        │
│   │             │   │             │   │             │   │             │        │
│   │ Label: CAT  │   │ Label: DOG  │   │ Label: CAT  │   │ Label: DOG  │        │
│   │  (Human)    │   │  (Human)    │   │  (Human)    │   │  (Human)    │        │
│   └─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘        │
│                                                                                 │
│   This is called "SUPERVISED LEARNING"                                          │
│   (Humans supervise by providing correct answers)                               │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Types of Learning

| Type | Labels? | Example | Data Needed |
|------|---------|---------|-------------|
| **Supervised** | Yes (humans label) | Cat vs Dog classifier | Labeled images |
| **Unsupervised** | No labels | Find patterns in data | Raw data only |
| **Self-Supervised** | Auto-generated | ChatGPT, LLMs | Text (predict next word) |

### How ChatGPT Was Trained (Self-Supervised)

```
Training Data: Billions of sentences from the internet

TASK: Predict the NEXT WORD

Input:  "The cat sat on the ___"

Model guess:    "dog"      ❌
Correct answer: "mat"      ✅  ← From actual text!

The "correct answer" comes from REAL TEXT that already exists!
No human labeling needed - the text itself IS the label.
```

### Real-World Datasets

| Dataset | Images | Categories | Labeled By |
|---------|--------|------------|------------|
| ImageNet | 14 million | 1,000 | Amazon Mechanical Turk workers |
| COCO | 330,000 | 80 | Human annotators |
| MNIST | 70,000 | 10 (digits) | Humans |

---

## Complete Training Iteration

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    ONE COMPLETE TRAINING ITERATION                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   ① LOAD BATCH                                                                  │
│      32 images with their labels                                               │
│                     │                                                           │
│                     ▼                                                           │
│   ② FORWARD PASS (Make predictions)                                            │
│      Model: "Dog, Dog, Cat, Dog, Dog..."                                       │
│                     │                                                           │
│                     ▼                                                           │
│   ③ CALCULATE LOSS (How wrong? Compare to labels)                              │
│      Got 20 right, 12 wrong → Loss = 0.375                                     │
│                     │                                                           │
│                     ▼                                                           │
│   ④ CALCULATE GRADIENTS (Which direction to fix?)                              │
│      Gradient: [-0.01, +0.03, -0.02, ...]                                      │
│                     │                                                           │
│                     ▼                                                           │
│   ⑤ UPDATE WEIGHTS (Adjust the brain)                                          │
│      Old weights + Gradient → New weights                                      │
│                     │                                                           │
│                     ▼                                                           │
│   ⑥ REPEAT with next batch...                                                  │
│                                                                                 │
│                              × 31,250 iterations = 1 EPOCH                     │
│                              × 100 epochs = FULL TRAINING                      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## NCCL (NVIDIA Collective Communications Library)

### What is NCCL?

NCCL handles GPU-to-GPU communication for distributed training.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         NCCL IN THE AI STACK                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   PyTorch / TensorFlow / JAX                                                    │
│            │                                                                    │
│            ▼                                                                    │
│   ┌─────────────────┐                                                           │
│   │     NCCL        │  ◄── Handles GPU-to-GPU communication                    │
│   └────────┬────────┘                                                           │
│            │                                                                    │
│     ┌──────┴──────┐                                                             │
│     ▼             ▼                                                             │
│ ┌───────┐    ┌────────┐                                                         │
│ │NVLink │    │  RDMA  │  ◄── Your 40GbE ConnectX-3!                            │
│ │(intra)│    │(inter) │                                                         │
│ └───────┘    └────────┘                                                         │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### NCCL Collective Operations

| Operation | What It Does | When Used |
|-----------|--------------|-----------|
| **AllReduce** | Sum/average data across all GPUs | Gradient sync (every batch!) |
| **Broadcast** | Send data from 1 GPU to all | Model init (once at start) |
| **AllGather** | Gather data from all GPUs to all | Collect validation results |
| **ReduceScatter** | Reduce + distribute chunks | Large model training |

### Why AllReduce is Critical

```
DISTRIBUTED TRAINING - GRADIENT SYNCHRONIZATION

Each GPU processes different images → different gradients
All GPUs must agree on how to update weights!

  GPU 0: Gradient A ─┐
  GPU 1: Gradient B ─┼──► NCCL AllReduce ──► Average Gradient ──► Update
  GPU 2: Gradient C ─┤
  GPU 3: Gradient D ─┘

AllReduce happens EVERY ITERATION (thousands of times per epoch!)
```

### Your Cluster - NCCL Over RDMA

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    YOUR CLUSTER - NCCL OVER RDMA                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   gpuserver1                              gpuserver2                            │
│   ┌────────────────┐                    ┌────────────────┐                      │
│   │  GPU0    GPU1  │                    │  GPU0    GPU1  │                      │
│   │   │       │    │                    │   │       │    │                      │
│   │   └───┬───┘    │                    │   └───┬───┘    │                      │
│   │       │        │                    │       │        │                      │
│   │   ConnectX-3   │                    │   ConnectX-3   │                      │
│   └───────┼────────┘                    └───────┼────────┘                      │
│           │                                     │                               │
│           └─────────── RDMA (80 Gbps) ─────────┘                               │
│                        0.85 µs latency                                          │
│                                                                                 │
│   NCCL AllReduce path:                                                          │
│   GPU0(srv1) ←→ GPU0(srv2) via RDMA                                            │
│   GPU1(srv1) ←→ GPU1(srv2) via RDMA                                            │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### NCCL Environment Variables

```bash
# Enable RDMA
export NCCL_IB_DISABLE=0
export NCCL_NET=IB

# Use both 40G ports (multi-rail)
export NCCL_IB_HCA=mlx4_0:1,mlx4_0:2

# RoCE settings (same as your perftest!)
export NCCL_IB_GID_INDEX=2

# Performance tuning
export NCCL_BUFFSIZE=4194304

# Debugging (use during testing)
export NCCL_DEBUG=INFO
```

### Impact of 0.85 µs RDMA Latency

| Training Config | Value |
|-----------------|-------|
| Batch size per GPU | 32 |
| Dataset size | 1,000,000 images |
| Batches per epoch | 31,250 |
| Epochs | 100 |
| **Total AllReduce calls** | **3,125,000** |

| Network | AllReduce Overhead per Epoch |
|---------|------------------------------|
| RDMA (0.85 µs) | ~2.7 seconds |
| TCP (21.9 µs) | ~68 seconds |
| **Savings** | **~65 seconds per epoch!** |

Over 100 epochs: **Save ~108 minutes** with RDMA vs TCP!

---

## Summary: Why This Cluster is Fast

| Component | What It Does | Your Performance |
|-----------|--------------|------------------|
| **V100 GPUs** | Compute (forward/backward pass) | 4x 16GB, Tensor Cores |
| **RDMA Network** | Gradient sync (AllReduce) | 80 Gbps, 0.85 µs |
| **NVMe Storage** | Load training data | 2.2 GB/s |
| **NCCL** | Coordinate GPUs | Uses RDMA automatically |

```
Training Speed Formula:
───────────────────────
Fast GPUs + Fast Network + Fast Storage = Fast Training

This Cluster:
V100 GPUs (fast) + RDMA (0.85 µs) + NVMe (2.2 GB/s) = Very Fast Training!
```

---

## Key Takeaways

1. **AI doesn't magically know** - humans provide labeled training data first
2. **Batch** = small group of samples processed together (fits in GPU memory)
3. **Epoch** = one complete pass through all training data
4. **Gradient** = direction to adjust model to reduce errors
5. **NCCL AllReduce** = sync gradients across GPUs (happens every batch!)
6. **RDMA** = makes AllReduce 26x faster than TCP
7. **Your 0.85 µs latency** = near-optimal for distributed training
