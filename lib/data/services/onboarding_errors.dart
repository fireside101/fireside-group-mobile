/// Public Group onboarding contract (src/lib/auth-errors.ts). Never display
/// arbitrary server/provider text; old error-only servers use exact safe text.
const onboardingErrorMessages = <String, String>{
  'INVALID_EMAIL': 'Enter a valid email address.',
  'PASSWORD_REQUIRED': 'Enter your password.',
  'PASSWORD_LENGTH': 'Use a password of 8–1024 characters.',
  'CONFIRM_PASSWORD_REQUIRED': 'Confirm your password.',
  'PASSWORD_MISMATCH': 'Passwords do not match. Re-enter your confirmation.',
  'INVALID_CREDENTIALS': 'Incorrect email or password. Please try again.',
  'ACCOUNT_UNVERIFIED': 'This existing account is not ready for sign-in. Contact HR or the Business Intelligence and Digital Engineering team for assistance.',
  'PI_INELIGIBLE': 'Your email is not in PI. Kindly contact HR or the Business Intelligence and Digital Engineering team for assistance.',
  'ACCOUNT_EXISTS': 'This account already exists. Sign in with your existing password or contact support for recovery.',
  'RATE_LIMITED': 'Too many attempts. Please wait before trying again.',
  'SERVICE_BUSY': 'Account service is busy. Please try again shortly.',
  'SERVICE_UNAVAILABLE':
      'Account service is unavailable. Please try again later.',
  'ORIGIN_NOT_ALLOWED': 'Request origin is not allowed.',
  'JSON_REQUIRED': 'Send a JSON request.',
  'INVALID_REQUEST': 'Invalid request.',
  'REQUEST_TOO_LARGE': 'Request is too large.',
  'SETUP_RETIRED': 'This setup link is retired. Return to email-first sign in or contact support.',
  'NOT_FOUND': 'Not found.',
};

const onboardingNetworkError =
    'Unable to connect. Check your connection and try again.';

String onboardingErrorMessage(int status, Map<String, dynamic> data) {
  // Transport throttling must remain visible even if a proxy replaces the body.
  if (status == 429) return onboardingErrorMessages['RATE_LIMITED']!;
  final code = data['code'];
  if (code is String && onboardingErrorMessages.containsKey(code)) {
    return onboardingErrorMessages[code]!;
  }
  final legacy = data['error'];
  if (legacy is String && onboardingErrorMessages.containsValue(legacy)) {
    return legacy;
  }
  return switch (legacy) {
    // The old endpoint combined provider verification with bad credentials;
    // do not falsely label that ambiguous legacy outcome as a wrong password.
    'Invalid email or password, or email verification is still required.' => 'Email or password is incorrect, or this account is not ready for sign-in. Contact support if your password is correct.',
    'Use a password of 8–1024 characters and a matching confirmation.' =>
      'Use a password of 8–1024 characters and a matching confirmation.',
    _ => onboardingErrorMessages['SERVICE_UNAVAILABLE']!,
  };
}

int? onboardingRetryAfter(int status, String? header) {
  if (status != 429 && status != 503) return null;
  final seconds = header != null && RegExp(r'^\d{1,5}$').hasMatch(header)
      ? int.tryParse(header)
      : null;
  if (seconds != null && seconds >= 1 && seconds <= 86400) return seconds;
  return status == 429 ? 900 : null;
}
