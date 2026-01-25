# AI & MCP Session Notes - January 2026

## Topics Covered

### 1. Versa AI-MCP (From Wiki)

We reviewed the Versa Networks wiki document about **AI-MCP** - using Model Context Protocol to manage Versa SASE/SSE via AI clients.

**Document Details:**
- Author: Arun Chandar
- Versa-OS: 22.1.4
- AI Clients Supported: Claude, Co-Pilot
- Concerto: 12.x

**What Versa AI-MCP Does:**
- Allows AI clients to manage Versa SASE/SSE through natural language
- MCP acts as a controlled middle layer between AI and Versa APIs
- All actions are validated, authorized, and auditable

**Use Cases:**
| Use Case | Description |
|----------|-------------|
| Tenant Onboarding | Rapid onboarding with validated baseline configs |
| Secure Client Access | Day-0 SAC policy setup |
| SAML Auth Profiles | Automated SAML profile management |
| Internet Protection | Deploy baseline protection policies |
| Config Audits | Identify misconfigs, compliance gaps, shadow rules |
| Policy Optimization | Fine-tune policies based on usage/risk |

**MCP Server Location:** 10.192.219.220 (Versa hosted)

**To Get Access:** Email arunc@versa-networks.com

---

### 2. MCP vs LLM - Key Differences

| | LLM | MCP |
|---|-----|-----|
| **Type** | AI Model (brain) | Protocol (hands) |
| **Examples** | Claude, GPT, Llama, DeepSeek | - (it's a standard) |
| **Purpose** | Understands language, generates responses | Lets LLMs interact with external systems |
| **Analogy** | The brain that thinks | The hands that do things |

**Key Insight:** MCP is NOT an LLM - it's a protocol that *extends* what LLMs can do.

---

### 3. Two Ways to Use AI for Versa Configuration

#### Option A: Give Docs to Claude → Claude Advises → You Execute

```
YOU: Share Versa docs
         ↓
CLAUDE: Reads, understands, generates configs
         ↓
YOU: Manually apply to Versa (you review before applying)
```

**Pros:** Safer, better for learning, more flexible
**Cons:** Slower, manual execution

#### Option B: Claude + MCP → Direct Execution

```
YOU: "Block gambling sites for Sales tenant"
         ↓
CLAUDE + MCP: Calls Versa API directly, makes change
         ↓
VERSA: Configuration applied automatically
```

**Pros:** Faster, automated
**Cons:** Requires MCP setup, paid Claude subscription, less visibility

---

### 4. Versa CLI Knowledge Test

**Question:** How to set IP address on vni-0/0 interface for VLAN 30?

**Answer - Hierarchical Mode:**
```
config
  interfaces vni-0/0
    unit 30
      vlan-id 30
      description "VLAN 30 - Management Network"
      family inet
        address 192.168.30.1/24
      enable
commit
```

**Answer - Set Commands:**
```
config
set interfaces vni-0/0 unit 30 vlan-id 30
set interfaces vni-0/0 unit 30 family inet address 192.168.30.1/24
commit
```

**Verification:**
```bash
show interfaces vni-0/0 unit 30 brief
show running-config interfaces vni-0/0
```

---

### 5. Methods to Customize AI for Internal Knowledge

| Method | Description | Effort | Best For |
|--------|-------------|--------|----------|
| **Fine-Tuning** | Retrain model weights with your data | High | Deep domain expertise |
| **RAG** | Give AI access to docs at query time | Medium | Searchable knowledge base |
| **In-Context Learning** | Paste docs in prompt | Low | Quick experiments |
| **MCP/Tools** | Connect AI to live APIs | Medium | Taking actions on systems |
| **RLHF** | Human feedback to align behavior | High | Behavior alignment |

**Recommendation:**
- Start with **RAG** for immediate value
- Collect Q&A examples during usage
- **Fine-tune** when you have 200+ examples

---

### 6. Storage Requirements for AI Workloads

| Approach | Storage Needed |
|----------|---------------|
| Running 7B model inference | ~5-15 GB |
| Running 13B model inference | ~10-26 GB |
| Running 32B model inference | ~20 GB |
| Running 70B model inference | ~40 GB |
| RAG system (docs + vector DB) | ~10-30 GB |
| Full fine-tune 7B | ~130 GB |
| QLoRA fine-tune 7B | ~10-15 GB |
| QLoRA fine-tune 13B | ~15-20 GB |

**Our Servers:** 232 GB each after LVM extension - plenty of room!

---

### 7. Fine-Tuning Data Privacy

**Key Concern:** Can training data be extracted from fine-tuned models?

**Answer:** Yes, models can "memorize" training data.

**Protection Strategies:**

| Strategy | Description |
|----------|-------------|
| Keep model private | Never publish fine-tuned models publicly |
| Sanitize training data | Remove passwords, real IPs, customer names |
| Use placeholders | `<PASSWORD>`, `<CUSTOMER_IP>` instead of real values |
| Differential privacy | Add noise during training (advanced) |
| Prefer RAG | Docs stored separately, not baked into model |

**Local Training = Private:** When training on your own GPUs, data never leaves your infrastructure.

---

### 8. Specialized AI Models

**Coding:**
- DeepSeek-Coder, CodeLlama, StarCoder

**Medical:**
- Med-PaLM 2, BioGPT, MedAlpaca

**Legal:**
- Harvey AI, LegalBERT

**Finance:**
- BloombergGPT, FinGPT

**Image Generation:**
- Stable Diffusion, SDXL, Flux, DALL-E

**Networking:**
- No major specialized model exists yet
- Opportunity to fine-tune your own for Versa/SDWAN!

---

## Key Takeaways

1. **MCP enables AI to take actions** - Not just chat, but actually configure systems
2. **Base LLMs have broad but shallow knowledge** - Need RAG or fine-tuning for deep expertise
3. **Your GPU cluster can run everything locally** - Private, no cloud dependency
4. **Start with RAG, fine-tune later** - Get immediate value, then improve over time
5. **Sanitize data before fine-tuning** - Protect sensitive information

---

## Links & Resources

- Versa AI-MCP Wiki: https://wiki.versa-networks.com/pages/viewpage.action?pageId=124702398
- MCP Access Request: arunc@versa-networks.com

---

*Last updated: January 22, 2026*
