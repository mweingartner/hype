---
type: reference
title: OpenAI model discovery in Preferences
description: Live OpenAI text and image model refresh triggers, fallback behavior, and limitations.
updated: 2026-10-24
---

# OpenAI model discovery

Preferences refreshes the text and image model dropdowns together from authenticated `GET /v1/models`
when OpenAI is selected, when Preferences opens with OpenAI selected, when an
OpenAI key is saved, and when **Refresh Models** or **Test OpenAI** is pressed.
Test OpenAI discovers models before sending its existing minimal test prompt;
a generation failure does not discard a successfully refreshed catalog. Opening
the AI tab also refreshes OpenAI's image choices when another text provider is
selected and an OpenAI key is saved; a **Refresh OpenAI Models** button remains
available there. Local speech settings do not trigger this image discovery.

The saved models remain selected and visible even if absent from the returned
catalog. Before successful discovery, the bundled lists are offline fallbacks.
Failed or empty discovery retains the previous choices and shows a generic
status. Catalogs are transient view state; replacing/deleting the key clears
the previous catalog and cancels stale requests. Closing Preferences cancels
pending discovery. Requests time out after at most 30 seconds.

OpenAI's listing endpoint includes other modalities and supplies no per-endpoint
capability flags. Hype therefore filters IDs using a text-family heuristic:
GPT-4.1, GPT-4o, GPT-5 and newer numbered GPT families, and o-series models,
including their fine-tuned IDs; known audio, image, realtime, search, instruct,
deep-research, and legacy o1 mini/preview variants are excluded. Discovery does
not guarantee every returned model supports all of Hype's tool/schema options.
Revisit this filter if OpenAI adds capability metadata or new naming families.

Image discovery accepts GPT Image and ChatGPT Image model families, including
new versions and snapshots. Models whose API shutdown date has passed are
excluded, as are retired GPT Image 1 and DALL·E models. The image fallback lists
all nine current IDs documented by OpenAI on 2026-10-24, including GPT Image 2.5
Sunburst/Flare and their snapshots. The live catalog reflects the saved API key's
access; discovery does not spend image-generation credits.

Discovery uses the existing Keychain credential and fixed OpenAI API host.
It sends no stack content, performs no generation, and exposes no raw server
error text in Preferences. Other text providers and speech choices keep their
existing behavior. The saved text and image selections are preserved.

Two primary research sources establish the listing contract and current image
families: [OpenAI List models API reference](https://developers.openai.com/api/reference/resources/models/methods/list)
and [Create image API reference](https://developers.openai.com/api/reference/resources/images/methods/generate).
The filtering policy is Hype's heuristic, rather than a guarantee from that API.
See also [architecture](../architecture.md#71-provider-clients) and
[decisions](../decisions.md#ai-and-tooling-guardrails).
