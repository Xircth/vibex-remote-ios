# VibeX iOS Companion

iOS Mobile companion for a VibeX Host. The phone never becomes a Host. Protocol and Host identity authority live in the VibeX repo; this context is the Companion client only.

## Language

### Host and pairing

**VibeX Host**:
The running owner of one VibeX data directory. The phone never becomes a Host.
_Avoid_: server (alone), backend, Codeg server

**Host identity**:
The stable id of that data directory. Profiles merge on this id, not on URL. After pairing, the canonical key is `ServerCapabilities.host_id`.
_Avoid_: baseUrl, server address as identity

**Host console**:
The admin surface on the machine running Host. This app is not the Host console.
_Avoid_: settings (when meaning listen / token / FRP)

**Reachability**:
One origin that can reach the same Host. A profile may have many.
_Avoid_: connection, tunnel (as the profile itself)

**Pairing invitation**:
A short-lived offer: Host identity, preset, all current Reachability, and a one-time secret for unpaired devices.
_Avoid_: QR (the invitation is the artifact; QR is one presentation), CODEG_TOKEN

**Device pairing**:
Redeeming an invitation into a long-lived, revocable device credential.
_Avoid_: login, API key, admin token

**Paired device**:
This installation's identity on one Host. Disconnect does not unpair.
_Avoid_: user account

**Companion Device**:
The permission preset of this app: session read/write, approve, steer, cancel, read-only artifact, offline cache.
_Avoid_: workstation, full remote desktop, mobile IDE

**Server profile**:
This app's local record of one Host: identity, name, Reachability list, last successful origin. Secrets stay in Keychain.
_Avoid_: server (the form fields)

**Forget server**:
Delete the local profile and credential; revoke this device when the Host is reachable.
_Avoid_: logout, disconnect (those keep the pairing)

**Remote disconnect**:
End the current network connection only. Profile, cache, credential, and pairing stay.

### Session and events

**Conversation**:
The durable dialogue with one agent, whose history is the event log.
_Avoid_: chat (as the domain name), session (when meaning Conversation)

**Turn**:
One user-start to agent-terminal cycle. At most one in flight per Conversation.

**Event log**:
The append-only authority for a Conversation. The phone folds it; it does not own it.
_Avoid_: websocket messages (as authority)

**Timeline row**:
The smallest independently updated line on screen, with a stable id and revision.

**Durable attach**:
ready → snapshot/replay → high-water → live, keyed by sequence.

**Queued conversation input**:
A persisted user intent not yet bound to a Turn.

**Turn steering**:
Guidance appended to a specific in-flight Turn. It is not a new Turn and must not silently become a queued input.

**Pending request**:
A permission, question, or blocked turn waiting on this user.

**Offline conversation cache**:
Read-only events through a confirmed sequence. Writes cannot queue while offline.

**Terminal notification summary**:
Ids, outcome, time, operation id. No prompt, output, or path.
