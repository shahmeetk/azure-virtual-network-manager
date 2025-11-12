# Azure Virtual Network Manager - Architectural Decisions and Routing Patterns

## Overview
This document outlines the architectural decisions and routing patterns implemented in the Azure Virtual Network Manager (AVNM) deployment architecture.

## 1. Virtual Network Gateway Architecture

### Decision: Conditional Gateway Deployment
- **Parameter**: `deployVirtualNetworkGateway: bool = true`
- **Rationale**: Provides flexibility to deploy hub environments with or without VPN/ExpressRoute connectivity
- **Deployment Sequence**: Gateway deploys before AVNM core resources to ensure proper dependency chain

### Gateway Module Features
- Supports both VPN and ExpressRoute gateway types
- Configurable SKU tiers (Basic, VpnGw1-5, ErGw1AZ-3AZ)
- Automatic zone redundancy for non-Basic SKUs
- Integrated public IP with DNS label
- BGP support with configurable ASN

## 2. Traffic Routing Patterns

### Core Principle: Hub-and-Spoke with Firewall Inspection
All traffic patterns enforce security inspection through the hub firewall:

#### Pattern 1: Spoke-to-Spoke Communication
```
Spoke1 → Hub Firewall → Spoke2
```
- **Implementation**: AVNM routing configuration with internal supernet routing
- **Security**: All inter-spoke traffic inspected by firewall
- **Performance**: Single hop through hub, optimized routing tables

#### Pattern 2: Internet-Bound Traffic
```
Spoke → Hub Firewall → Internet
```
- **Implementation**: 0.0.0.0/0 route to firewall private IP
- **Security**: All internet traffic inspected and filtered
- **Compliance**: Centralized logging and monitoring

#### Pattern 3: On-Premises Connectivity (with Gateway)
```
Spoke → Hub Firewall → VNet Gateway → On-Premises
```
- **Implementation**: Gateway subnet with UDR integration
- **Security**: Firewall inspection before on-premises routing
- **Redundancy**: Active-active gateway support

## 3. Security Admin Policies

### Traffic Enforcement Rules
Priority-based security rules ensure proper traffic flow:

1. **Priority 100-102**: Block high-risk protocols (RDP, SSH, SMB) from Internet
2. **Priority 200-201**: Allow HTTP/HTTPS to firewall for inspection
3. **Priority 300**: Deny direct internet access (force through firewall)
4. **Priority 400**: Allow spoke-to-spoke via firewall
5. **Priority 500-800**: Allow essential Azure services (DNS, AAD, KeyVault, Storage)
6. **Priority 4096**: Default deny all other traffic

### Rule Categories
- **Inbound Protection**: Block direct internet access to sensitive ports
- **Outbound Control**: Force all traffic through firewall inspection
- **Service Access**: Allow necessary Azure service communication
- **Spoke Isolation**: Ensure all inter-spoke traffic is inspected

## 4. Hub-and-Spoke Best Practices Implemented

### Connectivity Configuration
- **Topology**: Hub-and-Spoke with AVNM-managed peering
- **Gateway Transit**: Enabled for on-premises connectivity
- **Peering Management**: Automatic cleanup of manual peerings
- **Global Configuration**: Optional multi-region support

### IP Address Management (IPAM)
- **Pool-Based Allocation**: Centralized IP allocation from AVNM pool
- **CIDR Sizing**: Configurable VNet sizes (16-28 bits)
- **Overlap Prevention**: Built-in validation and conflict detection

### Network Groups
- **Dynamic Membership**: Tag-based auto-onboarding
- **Static Groups**: Hub network group for core services
- **Flexible Tagging**: Configurable tag names and values

## 5. Deployment Modes

### Management Group Mode
- **Scope**: Tenant-level deployment
- **Features**: Creates management groups, subscriptions, and VNets
- **Use Case**: New team onboarding with dedicated subscriptions
- **Dependencies**: Parent management group and billing scope

### Subscription Mode
- **Scope**: Current subscription
- **Features**: Creates resource groups and VNets only
- **Use Case**: Existing subscription utilization
- **Dependencies**: Existing subscription with proper permissions

## 6. Operational Considerations

### Monitoring and Logging
- Centralized logging through Azure Monitor
- Network flow logs for traffic analysis
- Security rule compliance monitoring
- Cost optimization through right-sizing

### Backup and Disaster Recovery
- Cross-region replication support
- Automated backup configurations
- Point-in-time restore capabilities
- Geo-redundant storage options

### Security Compliance
- Zero-trust network architecture
- Least-privilege access controls
- Encryption in transit and at rest
- Regular security assessments

## 7. Performance Optimization

### Routing Efficiency
- Optimized UDR rules to minimize hops
- Efficient route table propagation
- Reduced latency through direct paths
- Load balancing for high availability

### Scalability
- Modular architecture for growth
- Dynamic network group membership
- Automated IP pool management
- Policy-driven configuration

## 8. Troubleshooting Guidelines

### Common Issues
1. **Gateway Deployment Failures**: Check subnet sizing and IP availability
2. **Routing Issues**: Verify firewall IP configuration and UDR rules
3. **Security Rule Conflicts**: Check priority ordering and rule overlap
4. **Peering Problems**: Validate VNet IDs and subscription permissions

### Validation Steps
1. Verify gateway subnet creation and sizing
2. Confirm firewall private IP configuration
3. Test security admin rule effectiveness
4. Validate traffic flow patterns
5. Check AVNM configuration deployment status

## 9. Future Enhancements

### Planned Improvements
- ExpressRoute circuit integration
- Advanced threat protection
- Application security groups integration
- Network segmentation policies
- Automated compliance reporting

### Considerations
- Azure Policy integration
- Cost optimization algorithms
- Advanced monitoring dashboards
- Multi-cloud connectivity options