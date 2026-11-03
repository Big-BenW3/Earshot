/// Sign in with a Sui wallet (shared `sui_auth` package).
library;

import 'package:sqlite3/sqlite3.dart';
import 'package:sui_auth/sqlite.dart';
import 'package:sui_auth/sui_auth.dart';

import 'config.dart';

/// Cookie name unique to Earshot: browsers share cookies across localhost
/// ports, so a shared name would sign people out of the suite's other apps.
const sessionCookieName = 'earshot_session';

const signInStatement =
    'Sign in to Earshot to manage your shows. This does not send a '
    'transaction or cost gas.';

/// Sessions and nonces live in Earshot's SQLite file (tables `sui_auth_*`).
SuiAuth buildAuth(
  Config config,
  Database db, {
  SuiSignatureVerifier? verifier,
  DateTime Function()? clock,
}) {
  final store = SqliteSuiAuthStore(db);
  return SuiAuth(
    config: SuiAuthConfig.fromBaseUrl(
      config.signInOrigin,
      chain: config.suiChain,
      statement: signInStatement,
      cookieName: sessionCookieName,
    ),
    nonces: store,
    sessions: store,
    verifier: verifier,
    clock: clock,
  );
}
