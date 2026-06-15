import Foundation

/// A pragmatic "looks like an email" check to reject obvious non-emails BEFORE a round-trip to Clerk — specifically the `"Sign in with Apple"` / `"Hide My Email"` strings iOS autofill drops into the field, which a reviewer and real users keep submitting. Catching them client-side gives an instant inline hint instead of a server error, and keeps invalid input from firing a failure alert. Deliberately NOT RFC-complete; the real proof is the emailed code. Just `local@domain.tld` shape, no spaces.
func isValidEmailFormat(_ email: String) -> Bool {
    email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
}
