//! Bearer tokens: one for publishers, one for clients.

/// What a request's token allows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// May only publish items.
    Publish,
    /// May read and change items, but not publish.
    Client,
}

/// Finds which token the `Authorization` header carries.
///
/// The scheme name `Bearer` matches in any letter case. Returns `None` for a
/// missing or malformed header and for a token that matches
/// neither secret. Both tokens are always compared in constant time, so the timing
/// does not reveal which one came close. An empty secret never matches, and two
/// equal secrets match nothing: a misconfiguration then rejects every request
/// instead of granting both roles to one token.
pub fn classify(header: Option<&str>, publish_token: &str, client_token: &str) -> Option<Role> {
    // The auth scheme name is case-insensitive (RFC 9110 §11.1).
    let (scheme, token) = header?.split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("Bearer") {
        return None;
    }
    let given = token.as_bytes();
    let publish = !publish_token.is_empty() & constant_time_eq(given, publish_token.as_bytes());
    let client = !client_token.is_empty() & constant_time_eq(given, client_token.as_bytes());
    match (publish, client) {
        (true, false) => Some(Role::Publish),
        (false, true) => Some(Role::Client),
        _ => None,
    }
}

/// Compares two byte strings without stopping at the first difference.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    let diff = a
        .iter()
        .zip(b)
        .fold(a.len() ^ b.len(), |acc, (x, y)| acc | usize::from(x ^ y));
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    const PUBLISH: &str = "publish-secret";
    const CLIENT: &str = "client-secret";

    fn classify_header(header: Option<&str>) -> Option<Role> {
        classify(header, PUBLISH, CLIENT)
    }

    #[test]
    fn publish_token_gives_publish_role() {
        assert_eq!(
            classify_header(Some("Bearer publish-secret")),
            Some(Role::Publish)
        );
    }

    #[test]
    fn client_token_gives_client_role() {
        assert_eq!(
            classify_header(Some("Bearer client-secret")),
            Some(Role::Client)
        );
    }

    #[test]
    fn bearer_scheme_is_case_insensitive() {
        assert_eq!(
            classify_header(Some("bearer client-secret")),
            Some(Role::Client)
        );
        assert_eq!(
            classify_header(Some("BEARER publish-secret")),
            Some(Role::Publish)
        );
    }

    #[test]
    fn missing_header_is_rejected() {
        assert_eq!(classify_header(None), None);
    }

    #[test]
    fn malformed_header_is_rejected() {
        assert_eq!(classify_header(Some("client-secret")), None);
        assert_eq!(classify_header(Some("Basic client-secret")), None);
        assert_eq!(classify_header(Some("Bearer")), None);
        assert_eq!(classify_header(Some("Bearer ")), None);
        assert_eq!(classify_header(Some("")), None);
    }

    #[test]
    fn unknown_token_is_rejected() {
        assert_eq!(classify_header(Some("Bearer wrong")), None);
        assert_eq!(classify_header(Some("Bearer client-secre")), None);
        assert_eq!(classify_header(Some("Bearer client-secrets")), None);
        assert_eq!(classify_header(Some("Bearer  client-secret")), None);
    }

    #[test]
    fn empty_secret_never_matches() {
        assert_eq!(classify(Some("Bearer "), "", CLIENT), None);
        assert_eq!(classify(Some("Bearer "), PUBLISH, ""), None);
    }

    #[test]
    fn equal_secrets_match_nothing() {
        assert_eq!(classify(Some("Bearer same"), "same", "same"), None);
    }

    #[test]
    fn constant_time_eq_compares_length_and_bytes() {
        assert!(constant_time_eq(b"abc", b"abc"));
        assert!(!constant_time_eq(b"abc", b"abd"));
        assert!(!constant_time_eq(b"abc", b"ab"));
        assert!(constant_time_eq(b"", b""));
    }
}
