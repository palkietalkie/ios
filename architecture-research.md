# Architecture research

External references that inform the iOS architecture decisions (cascade vs speech-to-speech, model choices, etc.). Add new references as they come up.

## Speech-to-speech models (May 2026 survey)

- [nvidia/personaplex-7b-v1 - Hugging Face](https://huggingface.co/nvidia/personaplex-7b-v1) — NVIDIA, Jan 15 2026. Built on Moshi (Moshiko weights). Adds persona conditioning (voice prompt + text prompt). 0.170s turn-taking, 0.240s interruption latency. 7B params, A100/H100 server-side. Commercial license. The candidate to evaluate.
- [NVIDIA PersonaPlex - research page](https://research.nvidia.com/labs/adlr/personaplex/) — NVIDIA ADLR project page.
- [PersonaPlex preprint PDF](https://research.nvidia.com/labs/adlr/files/personaplex/personaplex_preprint.pdf) — full technical paper.
- [GitHub - NVIDIA/personaplex](https://github.com/NVIDIA/personaplex) — code, example prompts (astronaut / teacher / medical office), WebUI, offline demo command. 17 pre-built voices (NATF0-3, NATM0-3, VARF0-4, VARM0-4).
- [DataCamp PersonaPlex tutorial](https://www.datacamp.com/tutorial/nvidia-personaplex-tutorial) — step-by-step running guide.
- [PersonaPlex review (Kunal Ganglani)](https://www.kunalganglani.com/blog/nvidia-personaplex-full-duplex-voice-ai) — external review.

### Hosted demos (try without setup)

- [HF Space: MohamedRashad/PersonaPlex](https://huggingface.co/spaces/MohamedRashad/PersonaPlex) — community-hosted, fastest path to test in browser.
- NVIDIA's official project page demo: [research.nvidia.com/labs/adlr/personaplex](https://research.nvidia.com/labs/adlr/personaplex/).
- [Best Speech-to-Speech Model 2026: S2S Comparison - Inworld AI](https://inworld.ai/resources/best-speech-to-speech-model) — industry comparison of S2S models in 2026.
- [GitHub - huggingface/speech-to-speech](https://github.com/huggingface/speech-to-speech) — HF reference implementation for building local voice agents.

## TTS-only (not S2S — adjacent reference)

- [Mistral releases a new open source model for speech generation - TechCrunch (Mar 2026)](https://techcrunch.com/2026/03/26/mistral-releases-a-new-open-source-model-for-speech-generation/)
- VibeVoice (Microsoft) — long-form multi-speaker TTS, up to 90 min with 4 speakers
- Higgs Audio V2 (BosonAI) — built on Llama 3.2 3B, 10M+ hours training audio
- Dia (Nari Labs) — 1.6B dialogue TTS, English-only multi-speaker

## Foundational papers

- Moshi (Défossez et al., Kyutai, Sept 2024): `../papers/20240917-moshi-a-speech-text-foundation-model-for-real-time-dialogue.pdf`
