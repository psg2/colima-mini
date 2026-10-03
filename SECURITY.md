# Security policy

## Supported versions

Only the latest GitHub release and the current `main` branch receive security fixes.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub Security Advisories: open the repository's **Security** tab and choose **Report a vulnerability**. Don't open a public issue or pull request for security problems.

If private reporting isn't available, contact the maintainer through the links on the [psg2 GitHub profile](https://github.com/psg2).

Include the affected version, macOS version, Colima and Docker versions, reproduction steps and impact. Leave out real container logs, environment values and profile files unless they're essential to reproduce the issue.

## Scope notes

Colima Mini runs Docker and Colima commands on your behalf and reads local data:

- container logs and environment variables, which can hold credentials;
- the Colima profile, which the app edits to change VM resources;
- Compose project folders, which it reads to run Compose.

Reports about commands sent to the wrong Docker context, removals without confirmation or with force, secrets shown unmasked, unsafe edits to the Colima profile, insecure temporary files or unexpected network access are in scope. Report vulnerabilities in Colima, Docker or macOS to their maintainers.
