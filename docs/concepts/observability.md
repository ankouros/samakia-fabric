# Observability in Samakia Fabric

This document defines **how observability is designed, scoped, and applied**
in Samakia Fabric.

Observability is not monitoring dashboards.
It is **the ability to understand system behavior**.

---

## 1. Purpose of Observability

Observability exists to answer:

- What is happening?
- Why is it happening?
- What should we do next?

If these cannot be answered quickly,
observability has failed.

---

## 2. Observability Philosophy

Samakia Fabric follows these principles:

- Signal over noise
- Correlation over volume
- Determinism over guesswork
- Human-centric interpretation

Data without context is not observability.

---

## 3. The Three Pillars

Samakia Fabric uses the classic pillars:

| Pillar | Purpose |
|------|---------|
| Metrics | Quantitative system state |
| Logs | Discrete events and context |
| Traces | Causal relationships |

None are sufficient alone.

---

## 4. Scope of Observability

### 4.1 Infrastructure Level

Observed:
- Proxmox nodes
- LXC containers
- Network interfaces
- Storage health

Purpose:
- Capacity planning
- Failure detection
- HA validation

---

### 4.2 Platform Level

Observed:
- Kubernetes (if present)
- Databases
- Message queues

Purpose:
- Service health
- Dependency mapping
- Performance tuning

---

### 4.3 Application Level

Observed by:
- Application owners
- Platform tooling

Fabric does not impose application observability,
but enables it.

---

## 5. Metrics Strategy

### Characteristics

Metrics should be:
- Bounded
- Aggregatable
- Low cardinality

High-cardinality metrics are avoided.

---

### Examples

- CPU usage
- Memory pressure
- Disk IO
- Network throughput
- Restart counts

Metrics answer *what*, not *why*.

---

## 6. Logging Strategy

### Principles

Logs must be:
- Structured
- Time-synchronized
- Context-rich

Free-text logs are discouraged.

---

### Usage

Logs are used for:
- Incident investigation
- Security auditing
- Behavior analysis

Logs without retention policy are liabilities.

---

## 7. Tracing Strategy

Tracing is applied where:
- Latency matters
- Dependencies are complex
- Failures propagate

Not all systems need tracing.

Tracing without sampling is dangerous.

---

## 8. Observability and Immutability

Immutability simplifies observability:

- Known baselines
- Predictable changes
- Clear correlations

Mutable systems hide causality.

---

## 9. Observability and HA

Observability validates HA assumptions:

- Detect failovers
- Measure recovery time
- Expose partial failures

HA without observability is blind.

---

## 10. Observability and Security

Observability supports security by:
- Detecting anomalies
- Auditing actions
- Supporting forensics

Observability is not intrusion detection,
but it enables it.

---

## 11. Alerting Philosophy

Alerts exist to:
- Trigger action
- Escalate incidents

Alerts do NOT exist to:
- Mirror dashboards
- Report normal behavior

Every alert must have an owner.

---

## 12. SLOs and SLIs

Where applicable:
- SLIs define what is measured
- SLOs define what is acceptable

Not everything needs an SLO.

---

## 13. Observability and Automation

Automation consumes observability:

- Auto-scaling decisions
- Replacement triggers
- Health-based workflows

Automation without observability is reckless.

---

## 14. Anti-Patterns (Explicitly Rejected)

- Dashboard-driven operations
- Alert storms
- Unbounded logs
- Metrics without action
- Tool-first observability

Tools serve intent, not the opposite.

---

## 15. Observability and GitOps

Observability feeds GitOps by:
- Validating changes
- Detecting regressions
- Supporting rollback decisions

Git is the source of truth.
Observability is the source of reality.

---

## 16. Summary

In Samakia Fabric:

- Observability enables understanding
- Metrics, logs, and traces work together
- Signals drive action
- Automation depends on visibility

If you cannot explain what the system is doing,
you do not control it.
