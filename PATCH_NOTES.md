# Patch notes

## 1.0.0.0

- First version: the server keeps every player's role (super admin, admin, member) and makes admins admin again when
  they join. No password is stored.
- The first admin password login makes the super admin; later password logins make admins (can be turned off).
- Admin screen (Left Alt + A): player list with roles, details, promote / demote / make super admin, remove offline
  members, the "Remember password logins" setting.
- A demoted admin loses their rights right away and is locked out of the admin password.
