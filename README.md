# NoiseGuard

A decentralized urban sound pollution monitoring system built on the Stacks blockchain. NoiseGuard allows registered monitors to submit real-time noise level captures across defined geographic zones, with on-chain analytics compilation and collateral-backed participation to ensure data integrity.

---

## Overview

NoiseGuard enables a decentralized network of noise monitors to track acoustic pollution across a city. Monitors stake STX as collateral to participate, submit decibel readings by zone, and the contract aggregates this data into compiled analytics. The system includes spike detection to filter out erroneous readings and an expiration mechanism to ensure data freshness.

---

## Architecture

### Key Roles

- **Acoustic Supervisor** — The contract deployer (`tx-sender` at deploy time). Has exclusive authority to manage the whitelist of monitored zones.
- **Noise Monitors** — Any principal that registers and stakes the minimum collateral. They submit noise level captures for tracked zones.

### Data Flow

```
Register Monitor → Submit Captures → Compile Analytics → Query Analytics
```

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `MIN-MONITOR-COLLATERAL` | 1,000,000 µSTX (1 STX) | Minimum stake to register as a monitor |
| `MAX-LEVEL-AGE` | 144 blocks (~24 hours) | Analytics older than this are considered expired |
| `MAX-SPIKE` | 2,000 basis points (20%) | Maximum allowable change between consecutive readings |
| `MAX-RESOLUTION` | 18 | Maximum precision digits for a capture |

---

## Public Functions

### `register-monitor`

Registers the caller as a noise monitor and transfers `MIN-MONITOR-COLLATERAL` (1 STX) to the contract as a security deposit.

**Requirements:**
- System must be online
- Caller must not already be registered
- Caller must have sufficient STX balance

---

### `shutdown-monitor`

Deregisters the caller as a monitor and returns their collateral.

**Requirements:**
- System must be online
- Monitor must currently be active (online)

---

### `submit-capture (zone, level, resolution)`

Submits a noise level reading for a given zone.

| Parameter | Type | Description |
|---|---|---|
| `zone` | `string-ascii 32` | Zone identifier (must be in the monitored zones whitelist) |
| `level` | `uint` | Noise level value (must be > 0) |
| `resolution` | `uint` | Precision of the reading (0–18) |

**Validation performed:**
- System online check
- Monitor must be active
- Zone must be valid and whitelisted
- Level must be within bounds
- Resolution must be ≤ 18
- Level change from the previous capture for the same zone must not exceed 20%

---

### `add-monitored-zone (zone)` *(Admin only)*

Adds a zone identifier to the monitored zones whitelist. Only callable by the Acoustic Supervisor.

---

### `remove-monitored-zone (zone)` *(Admin only)*

Removes a zone from the whitelist. Only callable by the Acoustic Supervisor.

---

## Read-Only Functions

### `get-monitor-info (monitor)`
Returns registration data for a given monitor principal, including online status, collateral, precision score, total captures, and last capture block height.

### `get-noise-capture (zone)`
Returns the most recent raw noise capture for a zone (level, resolution, block height, capture count, submitting monitor).

### `get-compiled-analytics (zone)`
Returns compiled analytics for a zone: median, average, min, max levels, resolution, sample size, accuracy index, and last compilation block.

### `get-latest-analytics (zone)`
Returns compiled analytics with a freshness check. Returns `ERR-DATA-EXPIRED` if the last compilation is older than 144 blocks (~24 hours).

### `is-valid-monitor (monitor)`
Returns `true` if the monitor is online and holds sufficient collateral.

### `is-system-online`
Returns the current system online status.

### `get-total-monitors`
Returns the count of currently registered monitors.

### `calculate-spike (level1, level2)`
Returns the percentage difference between two level values in basis points (e.g., `1000` = 10%).

---

## Error Codes

| Code | Constant | Description |
|---|---|---|
| `u500` | `ERR-FORBIDDEN` | Caller is not authorized |
| `u501` | `ERR-MONITOR-EXISTS` | Monitor is already registered |
| `u502` | `ERR-MONITOR-OFFLINE` | Monitor not found or offline |
| `u503` | `ERR-LEVEL-INVALID` | Level value is out of bounds |
| `u504` | `ERR-DATA-EXPIRED` | Analytics data is stale (> 24 hours) |
| `u505` | `ERR-COLLATERAL-LOW` | Insufficient STX balance to register |
| `u506` | `ERR-MONITOR-DISABLED` | Monitor has been shut down |
| `u507` | `ERR-SPIKE-DETECTED` | Level change exceeds the 20% spike threshold |
| `u508` | `ERR-ZONE-INVALID` | Zone is empty, too long, or not whitelisted |
| `u509` | `ERR-RESOLUTION-INVALID` | Resolution value exceeds maximum |

---

## Data Maps

| Map | Key | Description |
|---|---|---|
| `noise-monitors` | `principal` | Monitor registration and stats |
| `noise-captures` | `zone` | Latest raw capture per zone |
| `compiled-analytics` | `zone` | Aggregated analytics per zone |
| `level-captures` | `{zone, monitor}` | Individual capture records for compilation |
| `monitor-collateral` | `principal` | Collateral amounts per monitor |
| `monitored-zones` | `zone` | Whitelist of valid zone identifiers |

---

## Security Considerations

- **Collateral staking** discourages monitor spam and dishonest data submission.
- **Spike detection** rejects readings that deviate more than 20% from the previous capture for a zone, mitigating sudden injection of false data.
- **Zone whitelisting** ensures only admin-approved zones can receive captures.
- **Data expiration** prevents stale analytics from being served as current.
- The Acoustic Supervisor constant is set at deploy time and cannot be changed — deploy carefully.

---

## Development Notes

- The `compiled-analytics` map must be populated by a separate compilation process (not yet implemented in this contract). The `level-captures` map stores unprocessed readings with a `processed` flag intended for use by a future compilation function.
- The `chief-acoustician` data variable is declared but not currently used in any function.
- Zone validation falls back to `true` when no whitelist entries exist, meaning the whitelist is only enforced once at least one zone has been added.