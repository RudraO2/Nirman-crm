// Story 1.1 — Canonical Edge Function error codes
// Source: architecture.md §API Error Codes
//
// Every Edge Function returns either { data: T } on success or { error: ApiError } on failure.
// HTTP status codes paired below.

export type ErrorCode =
  | "duplicate_lead"
  | "incomplete_required"
  | "interest_type_required"
  | "unauthorised"
  | "unauthorised_platform"
  | "account_locked"
  | "forbidden_role"
  | "forbidden_tenant"
  | "template_limit_reached"
  | "user_already_exists"
  | "validation_error"
  | "internal_error";

export interface ApiError {
  code: ErrorCode;
  message: string;
  details?: unknown;
}

export interface ApiSuccess<T> {
  data: T;
}

export type ApiResult<T> = ApiSuccess<T> | { error: ApiError };

export const HTTP_STATUS_FOR_CODE: Record<ErrorCode, number> = {
  duplicate_lead: 409,
  incomplete_required: 400,
  interest_type_required: 400,
  unauthorised: 401,
  unauthorised_platform: 403,
  account_locked: 429,
  forbidden_role: 403,
  forbidden_tenant: 403,
  template_limit_reached: 400,
  user_already_exists: 409,
  validation_error: 400,
  internal_error: 500,
};

export function errorResponse(
  code: ErrorCode,
  message: string,
  details?: unknown,
): Response {
  return new Response(
    JSON.stringify({ error: { code, message, ...(details !== undefined ? { details } : {}) } }),
    {
      status: HTTP_STATUS_FOR_CODE[code],
      headers: { "content-type": "application/json" },
    },
  );
}

export function successResponse<T>(data: T, status = 200): Response {
  return new Response(JSON.stringify({ data }), {
    status,
    headers: { "content-type": "application/json" },
  });
}
