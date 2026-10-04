# Case 3: When Automatic Database Failover Made the Outage Worse

## Module: Distributed Databases

## Learning Outcome

By the end of this case, you will be able to:  

1. **Explain** database failover, replication, failure detection, and the risks of automating distributed database recovery without considering performance and partition scenarios.

## Case type: Real incident, adapted for teaching

> **Important:** This is a lecturer-created teaching case based on [GitHub's](https://github.com/) public incident report. It has been paraphrased and reorganized for classroom use.

## Original technical incident report

**GitHub Blog:**  
https://github.blog/news-insights/github-availability-this-week/

An indexed copy on **[Postmortem.io](https://postmortem.io)**:  
https://postmortem.io/incidents/github--2012-09-10--github-availability-this-week/

---

## 1. Business context

GitHub operated a production MySQL environment supporting the GitHub.com platform.

The organisation had recently replaced an older database arrangement with a three-node cluster managed using high-availability software.

The architectural goal was straightforward:

> If the active database fails, another node should automatically become active.

The new design was intended to reduce downtime.

Instead, during a database migration and subsequent cluster problems, automated failover contributed to the incident.

---

## 2. The architecture

The system presented application services with virtual IP addresses.

Conceptually:

```text
                    Application
                         |
                    Virtual IP
                         |
             +-----------+-----------+
             |                       |
          Active                  Standby
        MySQL node              MySQL node
             |
             |
        Other cluster node
```

The cluster management system monitored database health.

If the active database appeared unhealthy, the system could automatically move the active role to another node.

This introduces an important assumption:

> A health check must correctly distinguish "the database is dead" from "the database is temporarily slow."

---

## 3. The triggering event

A database schema migration generated substantially more database load than expected.

The increased load caused the cluster's health checks to fail.

The cluster management software interpreted the failed health check as evidence that the active database had failed.

It therefore initiated a failover.

The replacement node had a cold database buffer pool and therefore performed poorly under the production workload.

The health checks then failed again.

The active role moved again.

The system entered a form of instability in which the mechanism designed to improve availability became a source of additional disruption.

---

## 4. A second complication: cluster partition

The incident also involved a partition in the cluster.

Different nodes did not always have a consistent view of cluster state.

This created the possibility that automated cluster-management actions could be taken based on incomplete or incorrect information.

The incident therefore illustrates several distributed-systems problems simultaneously:

- failure detection;
- false positives;
- failover;
- cluster coordination;
- partition;
- cold caches;
- workload-sensitive performance.

---

## 5. The central engineering question

The obvious question is:

> "Why did the database fail?"

A more interesting question is:

> **"What assumptions did the automated failover mechanism make about database health?"**

A database can be:

- completely unavailable;
- alive but slow;
- alive but overloaded;
- temporarily unable to answer a health check;
- reachable from one node but not another.

These states are not equivalent.

---

## 6. Questions for class discussion

### A. Distributed architecture

1. Why use database replication and failover?
2. What is the difference between high availability and high performance?
3. What is the purpose of a virtual IP in this architecture?
4. What happens during a failover?
5. What state must be transferred or preserved?

### B. Failure detection

6. What makes a good database health check?
7. Why can a health check produce a false positive?
8. Should a slow database be considered failed?
9. What additional evidence should be required before automatic failover?
10. How could multiple independent health signals improve failure detection?

### C. Distributed failure

11. What is a network partition?
12. Why is a partition particularly dangerous for automated failover?
13. What is split-brain?
14. How should a system prevent two nodes from simultaneously believing they are primary?

### D. Performance

15. Why did a cold buffer pool matter after failover?
16. Why can a technically healthy replica perform poorly when promoted?
17. Should failover readiness include performance testing?
18. How could the system warm or validate a standby before making it active?

### E. Design decision

19. Would you keep automatic failover for the primary production database?
20. If not, what would you automate instead?
21. If yes, what additional safeguards would you introduce?

---

## 7. Extension activity (Optional)

Design a failover policy using at least three signals:

1. database connectivity
2. replication health
3. query latency
