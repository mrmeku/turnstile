# OpenFGA glossary

The words `turnstile_fga` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Store | The server's isolation unit, holding tuples and the models published into it, named by the id the server gave it |
| Endpoint | Where the client talks: the address of a server, or the process a fake runs on |
| Model | The rules as the server holds them: immutable, published into a store, and named by the id the server answers with |
| Tuple | One relationship the store holds: a user, a relation, and an object, with a condition as a value on it |
| Tuple key | The user, the relation, and the object, which is what identifies a tuple and what a delete matches by |
| Condition | A name in the model and the parameters it carries, evaluated against the context a question is asked with |
| Object | The type and the id joined by a colon, which is the unit the store pages reads by |
| Tuple mapping | What an application states about its tables: the object types it writes, the objects of a type there are, the objects a change can have affected, and the tuples an object requires |
| Marker | One row of the outbox: an object whose tuples may have fallen behind the tables, written in the transaction that changed them |
| Outbox | The table those markers are written to, which the drain is a `Turnstile.Relay` runner over |
| Cursor | How far the drain has got, one row per runner in the application's own database |
| Drain | One pass: read a batch of markers above the cursor, write the difference per object, and delete the markers delivered, all in the pass's transaction |
| Difference | Per object, the tuples the rows require that the store lacks and the tuples it holds that the rows do not require |
| Check | The request that asks one tuple key against the model, answering yes or no and leaving no record of its own |
| Call | One `write/3`: its deletes and its writes applied together, counted together against the limit of one call, and refused where a tuple key is on both sides |
| Rewrite | A tuple key the difference asks to be deleted and written again, which takes two calls, the pass committing after the second |
| Reconcile | The comparison of the tables with what the store reports, paged by object type, answering what each holds and the other does not |
| Rebuild | A store created, the model published into it, and every object the tables hold written into it, beside the store that is serving |
| Fake | The client behaviour on an `Agent`: stores, models, and tuples, refusals as the server makes them, and no model evaluated |
