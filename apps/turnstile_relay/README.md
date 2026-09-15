# Turnstile relay

Batched, ordered delivery from a Postgres table, on its way into `turnstile_fga` as `Turnstile.Fga.Relay`. The one job in this repository is the OpenFGA outbox, and a package with one user is a module of that user. Until the fold lands, the mechanism is described in the `turnstile_fga` README under "One pass of the relay", and the modules here are the ones that README names with `Turnstile.Relay` in place of `Turnstile.Fga.Relay`.
