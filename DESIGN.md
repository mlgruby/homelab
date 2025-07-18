# Homelab Design Document

This document outlines the architecture and setup for a high-performance,
declarative homelab.

## 1. Project Goals

- To create a resilient, multi-node homelab for hosting various services.
- To manage the entire infrastructure declaratively (Infrastructure as Code).
- To establish a robust, automated backup and recovery strategy.

## 2. Hardware Inventory

- **Compute Cluster (3x nodes):**
  - **Model:** Intel NUC
  - **CPU:** Intel N150
  - **RAM:** 32 GB DDR4
  - **OS Drive:** 256 GB NVMe SSD
  - **Fast Tier Storage:** 1 TB NVMe SSD
- **Central Storage (1x node):**
  - **System:** 4-bay NAS running TrueNAS
  - **Storage:** 16 TB in a RAID-Z1 configuration

## 3. Core Software Architecture

The homelab will be built on a fully declarative, GitOps-driven model.

- **Operating System:** **NixOS** on all compute nodes for reproducible,
  declarative system configuration.
- **Orchestrator:** **k3s**, a lightweight, certified Kubernetes distribution.
  This will be used to manage containerized applications across the 3-node
  cluster.
- **Deployment Tool:** **deploy-rs** will be used to deploy NixOS configurations
  from a central Git repository to the nodes.
- **Application Deployment:** **FluxCD** will be installed on the k3s cluster to
  manage application deployments using a GitOps workflow.

## 4. Node Setup & OS Installation

This is the **one-time manual setup** required for each of the three NUCs before
declarative management can take over.

### 4.1. OS Drive Partitioning

The 256GB OS drive will use a simple and standard UEFI layout.

| Partition | Type                       | Filesystem | Size              | Mount Point | Purpose                                    |
| :-------- | :------------------------- | :--------- | :---------------- | :---------- | :----------------------------------------- |
| 1         | EFI System Partition (ESP) | `FAT32`    | 1 GB              | `/boot`     | For the `systemd-boot` UEFI bootloader.    |
| 2         | Linux Filesystem           | `ext4`     | Rest of the drive | `/`         | The NixOS root filesystem.                 |

**Note:** No swap partition will be created. A swap file can be added
declaratively via NixOS configuration if needed later.

### 4.2. Initial Installation Steps

1. Create a bootable USB drive with the minimal NixOS installer.
2. Boot the NUC from the USB drive.
3. Partition the 256GB OS drive as described above.
4. Generate a basic NixOS configuration (`nixos-generate-config`).
5. Edit `/etc/nixos/configuration.nix` to include:
    - A unique hostname (`nuc1`, `nuc2`, `nuc3`).
    - An admin user with your SSH public key for `deploy-rs`.
    - Enablement of the OpenSSH server.
6. Run `nixos-install` to install NixOS to the drive.
7. Reboot and verify SSH access from your management machine.

## 5. Storage Architecture

A two-tiered storage model will be used to balance performance and bulk
capacity.

### 5.1. NUC Onboard Storage (High-Performance Tier)

The 1TB NVMe drive in each NUC will be used for high-performance operations.

1. **Preparation:** The drive will be formatted with an `ext4` filesystem and
   mounted at `/data`.
2. **Path A - Cluster Operations:** The `/var/lib/rancher` directory (k3s's
   default data path) will be located on this drive (e.g., at `/data/k3s`). This
   accelerates container image caching and overall cluster performance.
3. **Path B - Fast Persistent Volumes:** The `local-path-provisioner` in k3s will
   be configured to use a directory on this drive (e.g., `/data/k8s-volumes`)
   to provide high-IOPS `local-persistent-volumes` for demanding applications
   like databases.

### 5.2. TrueNAS Storage (Reliable Bulk Tier)

The TrueNAS will serve as the primary, centralized data store.

- **Protocol:** **NFS** will be used to share storage from the TrueNAS to the
  k3s cluster. It supports `ReadWriteMany` volumes, which are highly flexible
  for Kubernetes. iSCSI is not required.
- **Usage:** This NFS share will provide persistent volumes for the majority of
  applications that do not require extreme IOPS.
3
## 6. Configuration & Deployment

- **Source of Truth:** A single Git repository will contain all NixOS
  configurations for the nodes and all Kubernetes manifests for the
  applications.
- **OS Management:** The `deploy-rs` tool will be used to push changes from the
  NixOS configuration in Git to the three NUCs.
- **Application Management:** The **FluxCD** GitOps agent will run inside k3s.
  It will monitor the Kubernetes manifest directory in the Git repo and
  automatically apply any changes to the cluster.

## 7. Backup & Recovery Strategy

A two-pronged, automated strategy will ensure all data is backed up.

### 7.1. Normal Apps (Data on TrueNAS)

- **Tool:** Native TrueNAS (ZFS) features.
- **Process:**
    1. **Snapshots:** Configure a **Periodic Snapshot Task** on TrueNAS to take
       nightly, point-in-time snapshots of the main NFS share.
    2. **Replication (Off-site):** Configure a **Replication Task** to
       automatically send these ZFS snapshots to an off-site location (e.g., a
       cloud S3 bucket like Backblaze B2).

### 7.2. High-Performance Apps (Data on NUCs)

- **Tool:** **Velero**, the Kubernetes-native backup tool.
- **Process:**
    1. **Backup Destination:** An S3-compatible object store is required by Velero
       for optimal performance, portability, and reliability. While other methods
       exist, using an S3-compatible backend is the industry standard and the most
       robust solution, ensuring backups are portable for disaster recovery.
        - **Implementation:** **MinIO** will be used to provide this S3 backend.
        - **Deployment:** MinIO will be installed as an official **TrueNAS App**.
          This ensures it is properly managed and isolated. The performance
          overhead on TrueNAS is negligible as MinIO is lightweight and only
          active during the short backup window.
        - **Storage:** A dedicated ZFS dataset will be created on the TrueNAS to
          store the MinIO buckets, cleanly isolating the backup data.
    2. **Scheduled Backups:** Velero will be configured with a schedule to back up
       the state (Kubernetes objects) and data (persistent volumes) of
       high-performance applications from their local NVMe drives to the MinIO
       S3 bucket on the TrueNAS.

### 7.3. Unified Off-site Backup

The TrueNAS **Replication Task** will be configured to send both the ZFS
snapshots (normal apps) and the contents of the MinIO bucket (Velero backups for
high-performance apps) to the final off-site destination. This centralizes and
automates the disaster recovery plan.
