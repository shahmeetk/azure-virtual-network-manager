### Team Onboarding parameters guide (infrastructure/spoke-team-onboarding/main.parameters.json)

This guide documents every parameter used by `infrastructure/spoke-team-onboarding/subscription-main.bicep`. Since JSON doesn’t allow comments, keep this guide next to your parameters file.

How to deploy
- What-if (safe preview):
  ```bash
  ./scripts/onboard-team.sh \
    --subscription <context-sub-id> \
    --location eastus \
    --params infrastructure/spoke-team-onboarding/main.parameters.json \
    --what-if
  ```
- Actual deployment:
  ```bash
  ./scripts/onboard-team.sh \
    --subscription <context-sub-id> \
    --location eastus \
    --params infrastructure/spoke-team-onboarding/main.parameters.json
  ```

Parameters
- Same as previously documented for subscription-mode team onboarding.

Change Log
- 1.1.1: Updated paths to `infrastructure/spoke-team-onboarding`.