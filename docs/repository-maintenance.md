# Glow Fork Maintenance

Last audited: 2026-07-26

`Thetromboneman1/Glow` is an active GitHub fork of `dayanch96/Glow`. Source and
localization changes come from upstream `main`. Downstream differences are
limited to workflow hardening, automated review-branch synchronization,
validation, and this maintenance documentation.

The build workflow remains manual because it requires a user-authorized
decrypted IPA URL. The URL is masked, passed through an environment variable,
and never committed. The resulting IPA is published only as a draft release.

The upstream sync workflow runs weekly and on manual dispatch. It:

- fetches the authoritative upstream with three bounded attempts;
- preserves downstream workflow and governance files;
- merges only into `automation/upstream-sync-<sha>`;
- validates before pushing;
- opens or reuses a pull request; and
- records conflicts in an issue without changing `main`.

Email delivery is not active. This is a public repository and cannot consume
the private Boneman notification action. The five `M365_*` secrets are also not
provisioned because the Boneman-scoped 1Password automation path is blocked.

Maintenance status: active downstream fork.
