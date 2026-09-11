# Integration & QA — run after Agents A, B, and C each finish

This is not one of the three build agents' jobs — it's the checklist for whoever (you, or a coordinating agent) verifies the three pieces actually work together once each has hit their own acceptance criteria.

## Order of integration

1. Confirm Agent A's server is deployed and its `wscat`-based tests still pass.
2. Bring Agent B's Mac app up against the real deployed server; complete pairing manually via a temporary test client or Agent C's real app.
3. Bring Agent C's iPhone app up against the same server and Agent B's app.
4. Only once both apps are talking to the *same real deployed signaling server* (not localhost stand-ins) should you consider the individual agents' work "integrated."

## End-to-end test matrix

- [ ] Pairing over the internet with Mac and iPhone on **different networks** (e.g. Mac on home Wi-Fi, iPhone on cellular) — this is the test that actually proves TURN/STUN and the signaling server work correctly together; testing both devices on the same LAN can hide NAT traversal bugs.
- [ ] Video quality and latency on a normal home broadband connection.
- [ ] Video quality and latency on the iPhone over cellular (LTE/5G), Mac on home Wi-Fi.
- [ ] Full click/drag/scroll/type input round trip, verified against both the Mac's native display and an external monitor with a different aspect ratio and a different scale factor (Retina vs non-Retina if you can test both).
- [ ] Denying a pairing request on the Mac correctly stops the iPhone from proceeding.
- [ ] Force-quitting and reopening the iPhone app reconnects via stored token without a full re-pair.
- [ ] Mac sleep → wake mid-session: session either gracefully recovers or cleanly ends with clear UI on both sides, never silently hangs.
- [ ] Network drop on either device recovers automatically within a reasonable window (define what "reasonable" means for your use case, e.g. under 15 seconds) or fails with a clear, actionable message.
- [ ] The "being controlled" indicator on the Mac is visible for 100% of the time a session is active, verified by literally watching the Mac screen during a full test session, not just checking logs.
- [ ] Multiple pairing/unpairing cycles don't leak stale tokens or leave the Mac in a state where it still shows an old device as connected.

## Known v1 limitations to note (not bugs, just scope)

- No support for hosts other than macOS or controllers other than iOS.
- `text_input` handles standard ASCII/punctuation; full Unicode/IME input (e.g. non-Latin scripts) is a known gap.
- No clipboard sync between devices.
- No multi-monitor picker UI on first release (host streams whichever display it's configured to capture; switching displays live is a stretch goal, not a v1 requirement unless you decide otherwise).

## What to do if something doesn't match the protocol contract

If integration reveals that two agents built to subtly different interpretations of a message shape, the fix is: update `00_PROJECT_CONTEXT_AND_PROTOCOL.md` first with the corrected, unambiguous version, then patch both sides to match it — don't patch just one side to work around the other, or the contract document stops being trustworthy for future changes.
