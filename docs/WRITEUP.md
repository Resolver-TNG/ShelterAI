# ShelterAI — Offline AI Shelter Registration Powered by Gemma 4

**Tracks: Main | Global Resilience | Cactus (Local-First Mobile)**

---

## The Reality of Disaster Shelters

When the Noto Peninsula earthquake struck Japan on January 1, 2024, thousands of evacuees arrived at community centers and school gymnasiums. Volunteers registered each person with paper forms and pens — and that worked. Paper is resilient. It needs no battery, no network, no training. In disaster response, paper has earned its place.

But paper also has limits. When a shelter holds 500 people and one volunteer is trying to figure out how many need wheelchairs, how many infants need formula, or who among the injured should be prioritized — flipping through handwritten forms takes time that people may not have.

Japan's Digital Agency ran a proof-of-concept showing that digital ID processing cuts per-person intake from 90 seconds to 9. The problem is that every existing solution requires internet connectivity, paid subscriptions, or proprietary hardware — exactly the resources that disappear when they are needed most.

Meanwhile, something has quietly changed. Nearly every evacuee now arrives with a smartphone in their pocket. Mobile batteries are everywhere — convenience stores rent them, evacuation centers set up charging stations. The computing power is already in the room. The question is whether we can put it to use.

ShelterAI is one answer to that question: a free, fully offline iPhone app that turns an everyday device into a shelter registration tool. Not a replacement for paper — another option alongside it.

---

## How It Works

A volunteer photographs an evacuee's ID card. The app does the rest.

1. **Capture** — Point the camera at any Japanese ID card. Real-time rectangle detection finds the card edge; after 1.4 seconds of stable detection, auto-shutter fires. No tap needed.
2. **Analyze** — Gemma 4 E2B, running entirely on-device, extracts name, address, date of birth, and card type as structured JSON. Vision OCR runs in parallel as a cross-check.
3. **Confirm** — Extracted fields displayed for the evacuee to verify. Editable if corrections are needed.
4. **Register** — Saved to local SQLite with GPS timestamp, injury status, body-part details, and special-needs flags.
5. **Assist** — AI Assistant answers shelter operations questions. Situation Dashboard shows real-time statistics and supply estimates based on government guidelines.

Supported cards: My Number Card, driver's license, passport (MRZ), residence card, health insurance card. The entire flow takes 6–10 seconds. No internet at any step. Personal data never leaves the device.

---

## Technical Architecture

### Why Gemma 4 E2B

Japanese ID parsing is a multimodal problem: five card types with different layouts, mixed scripts (kanji, hiragana, katakana, Latin, Arabic numerals), Japanese era dates, and fields that only make sense through visual context. A text-only OCR pipeline would need card-specific templates for each format. Gemma 4 E2B sees the card as a whole and returns structured JSON from a single prompt.

The E2B variant (2B effective parameters) fits the constraint: ~2.7 GB in CoreML Int4, leaving headroom on 6 GB iPhone RAM. Inference takes 2–8 seconds on Apple Neural Engine — within the UX window for form fill-in. Larger models would exceed 30 seconds.

### Intelligent Routing

The core technical insight emerged from real-device testing. A 2B model handles flexible, unstructured tasks well — multimodal extraction, free-form Q&A about shelter operations ("How do I set up a drum-can bath for hygiene?"). But it struggles with structured data retrieval: it couldn't reliably cross-reference evacuee counts across context sections.

Rather than fighting the model's limitations, we split the workload:

| Query Type | Path | Accuracy | Latency |
|---|---|---|---|
| **Card analysis** | Gemma 4 E2B + Vision OCR fallback | Hybrid, confidence-gated | 5–15s |
| **Preset questions** (5 types) | Swift code → database aggregation | 100% deterministic | Instant |
| **Free-form questions** | Gemma 4 E2B → streaming | Best-effort | 3–10s |

Preset buttons (injury triage, supply estimates, special-needs roster, summary, foreign resident support) deliver instant, name-by-name accurate answers generated entirely from the database. Free-form questions go to Gemma 4, which handles open-ended shelter knowledge naturally. Each query reaches the system best suited to answer it.

### Three-Layer Card Analysis

A confidence-gated fallback ensures maximum coverage:

1. **Gemma 4 E2B** — Multimodal inference. Confidence ≥ 0.8: accept directly. < 0.5: fall through.
2. **Vision OCR** — Apple's VNRecognizeTextRequest with MRZ parser for passports. Runs in parallel; fields merged in the mid-confidence range (0.5–0.8).
3. **Manual input** — Empty form when automated paths produce insufficient output. No data is fabricated.

Image preprocessing normalizes every capture: rectangle detection → perspective correction → contrast boost (+10% for dim gymnasium lighting) → downscale to 1024px.

---

## What the App Actually Does: 30 Features

Beyond the AI pipeline, ShelterAI is a working shelter management system built across 38 Swift files and 6,326 lines of code.

**Registration:** Auto-shutter camera, hybrid AI+OCR extraction, manual input with 15-region injury body-part picker, family-group inference (same surname + address block), privacy consent gate, rate limiting (5/min), GPS stamping, voice announcements (Japanese TTS)

**AI Assistant:** 5 deterministic presets — injury triage sorted by severity with body-part details, supply calculation per Cabinet Office guidelines, special-needs roster with names, overall summary, foreign resident support with action items. Plus free-form Gemma 4 Q&A for general shelter operations knowledge.

**Situation Dashboard:** Real-time statistics (age/gender/injury/special-needs breakdown), supply estimation slider (1–30 days) computing water, food, blankets, diapers, formula, sanitary products, and medical kits per person per day. Foreign resident detection via name heuristics.

**Data Management:** GRDB/SQLite with 5 schema migrations, searchable list with attribute filters, individual record deletion, CSV export (UTF-8 BOM for Excel compatibility), distribution tracking with per-evacuee checklists. **The CSV handoff is a deliberate design choice:** shelters collect data offline during the crisis phase, then export structured records to municipal officials, Self-Defense Forces, or relief organizations once communication is restored — via AirDrop, USB, or email. No cloud sync, no API integration, no vendor lock-in. Just a file that any spreadsheet can open.

**Privacy:** Zero network calls in the entire codebase. No analytics, no telemetry. Two dependencies total (GRDB.swift, CoreML-LLM). Explicit consent screen before every save. Test-mode data auto-deleted on app termination.

---

## Impact

At a 500-person shelter:
- **Paper:** ~12.5 hours at 90 seconds per person
- **ShelterAI:** ~0.8 hours (Gemma path) to ~1.4 hours (OCR fallback)
- **Difference:** 11+ hours of volunteer time redirected to care, distribution, and coordination

The architecture is portable: card types are configurable via enum and prompt template. Residence card support already handles multinational scenarios. Deploying to 1,000 devices serving 1,000 shelters requires zero server infrastructure.

---

## Why Open Source

This is not a manifesto. It is a wish.

I have spent 11 years building systems — servers, clouds, AI pipelines. I have never experienced a major disaster firsthand. But I have read the after-action reports. I have seen the photographs of gymnasium floors covered in paper forms where volunteers worked through the night. And I keep coming back to the same thought: the tools to help in those first critical hours already exist on the devices people carry every day. They just cost too much, require infrastructure that does not survive, or sit behind procurement cycles that move slower than earthquakes.

ShelterAI is released under Apache 2.0 because I believe disaster preparedness belongs in the commons. A municipal government in the Philippines, an NGO in earthquake-prone Turkey, a volunteer team anywhere — they should be able to fork this, adapt it, and deploy it without asking permission or opening a purchase order.

If even one shelter somewhere uses a descendant of this code to register evacuees faster, to identify injured people sooner, to count how many blankets are needed before nightfall — then this project did what it was meant to do.

Open source disaster response is not a business model. It is a prayer from one engineer that the next time the ground shakes, the technology is already there, already free, already working.

---

*Built for the shelters that have no internet, no budget, and no time — where a phone with Gemma 4 is the only extra tool that fits in a volunteer's pocket.*
