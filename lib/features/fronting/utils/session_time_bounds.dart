/// Effective end for an open (null-end) session in overlap and containment
/// math: "no end yet" is treated as far-future so an active session compares
/// after every real one. UTC keeps it timezone-independent. Only ever compared
/// — never stored, returned, or shown.
final DateTime farFutureSessionEnd = DateTime.utc(9999);
