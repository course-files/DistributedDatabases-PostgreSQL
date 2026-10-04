# Case 4: The Five Seconds of Missing Payment Data

## Module: Distributed Databases

## Learning Outcome

By the end of this case, you will be able to:  

1. **Analyze** replication, durability, failover, consistency, and recovery as interacting properties rather than independent database features.

## Case type: Real incident, adapted for teaching

> **Important:** This is a lecturer-created teaching case based on [Razorpay's](https://razorpay.com/) public incident report. It has been paraphrased and reorganized for classroom use.

## Original technical incident report

**Razorpay Tech:**  
https://razorpay.com/blog/day-of-rds-multi-az-failover/

An indexed copy on **[Postmortem.io](https://postmortem.io)**:  
https://postmortem.io/incidents/razorpay--unknown--rds-multi-az-failover-data-loss/

---

## 1. Business context

Razorpay operates payment infrastructure where database correctness is particularly important.

A production application used Amazon RDS for MySQL with a Multi-AZ configuration. In addition, several read replicas supported application workloads.

The architecture was intended to provide:

- automatic failover;
- database availability;
- read scalability;
- protection against infrastructure failures.

The system experienced a database failover.

The application recovered automatically.

The incident initially appeared to be over.

It was not.

---

## 2. Initial failure

The production MySQL instance experienced a Multi-AZ failover.

For roughly two minutes, the application experienced connection errors.

The database then became available again.

However, shortly afterward, the team discovered that replication to several read replicas had failed.

The team temporarily redirected read traffic from replicas to the primary.

This protected users from potentially stale data, but it increased CPU utilisation on the primary.

The team therefore had two competing objectives:

> Keep the application available.

and

> Avoid serving incorrect or stale information.

---

## 3. The investigation

The engineering team compared:

- application traces;
- database logs;
- binary logs;
- database contents;
- replica behaviour.

They discovered that some operations recorded in application traces did not appear in the newly promoted primary database.

The discrepancy was approximately five seconds of transactional data.

For a payment platform, five seconds of missing transactional information is serious.

The team therefore had to determine:

> How could a transaction have been considered committed by the application while not being present on the database instance that became primary?

---

## 4. The configuration clue

The investigation uncovered an important MySQL configuration:

`innodb_flush_log_at_trx_commit`

The relevant settings can be simplified as follows:

- `1`: flush the InnoDB log at transaction commit;
- `2`: write the log at commit but flush it to disk approximately once per second;
- `0`: write and flush less frequently.

The production system had been configured with a value that did not provide the same durability characteristics as the default setting expected by the team.

At the same time, binary logging was configured differently.

This created an important distinction between:

1. a transaction having reached the database process;
2. a transaction having been logged;
3. a transaction having been durably flushed;
4. a transaction being present on the standby that will become primary.

---

## 5. Why replicas also behaved strangely

The binary logs contained operations that had occurred during the affected period.

The read replicas therefore attempted to apply operations that had not become durable on the standby that was promoted.

This contributed to duplicate-key replication errors.

The result was a complex situation:

```text
Application transaction
        |
        +----> Primary log / binary log
        |
        +----> Storage durability
        |
        +----> Standby
        |
        +----> Read replicas
```

These paths did not necessarily become durable at exactly the same point in time.

---

## 6. Questions for class discussion

### A. Replication

1. What is the difference between synchronous and asynchronous replication?
2. What is the difference between a standby used for failover and read replicas used for scaling?
3. Why can a read replica contain a different state from the primary?
4. What does replication lag mean?
5. What guarantees should an application expect from a read replica?

### B. Durability

6. What does "committed" mean from the perspective of a database transaction?
7. Is a committed transaction necessarily safe if the server immediately loses power?
8. What is the relationship between transaction commit, write-ahead logging, flushing, and durable storage?
9. Why does `innodb_flush_log_at_trx_commit` matter?

### C. Failover

10. What should happen to transactions that were in progress during failover?
11. What is the difference between availability and durability?
12. Can automatic failover guarantee zero data loss?
13. What does RPO mean in this context?
14. What does RTO mean?

### D. Architectural trade-offs

15. Why might an organisation deliberately accept a small durability risk?
16. What performance benefit might a less durable configuration provide?
17. Is that trade-off acceptable for a payment platform?
18. What other controls could compensate for the risk?

### E. Recovery

19. Why was redirecting all reads to the primary only a temporary solution?
20. Why was rebuilding replicas necessary?
21. How could application-level idempotency help during recovery?
22. What role did binary logs play in reconstructing the missing information?

---

## 7. Extension activity (Optional)

Design a payment architecture with explicit:

- RPO;
- RTO;
- replication mode;
- failover policy;
- read-consistency policy;
- reconciliation mechanism.

Then answer the following question:

> Which guarantees would you be willing to weaken to reduce cost or latency?
