# Archive

This folder contains deprecated modules and scripts that have been consolidated or replaced. They are retained temporarily for reference. All active deployments now use the unified modules.

Deprecated items archived here:
- 1-platform-deployment/hub/modules/avnm-configs-min.bicep (replaced by modules/avnm-configs.bicep)
- 1-platform-deployment/hub/modules/connectivity-autoprobe.bicep (replaced by native connectivity in modules/avnm-configs.bicep)
- 1-platform-deployment/hub/modules/avnm-policy-sub.bicep (replaced by unified modules/avnm-policy.bicep)
- 1-platform-deployment/hub/mg-avnm-policy.bicep (use unified modules/avnm-policy.bicep with scopeType="ManagementGroup")
- scripts/connectivity-autoprobe.sh (deprecated)

Use these only as historical reference; do not invoke them in new deployments.
