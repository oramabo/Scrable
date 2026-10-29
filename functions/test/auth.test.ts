import { bearerToken, requireAdmin, requireAuth, secretsEqual } from '../src/lib/auth';
import { daysBetween, isoDate, parseIsoDate } from '../src/lib/time';

type Req = Parameters<typeof requireAuth>[0];

describe('auth helpers', () => {
  test('requireAuth / requireAdmin', () => {
    expect(() => requireAuth({ auth: undefined } as Req)).toThrow(expect.objectContaining({ code: 'unauthenticated' }));
    const user = { auth: { uid: 'u1', token: { admin: false } } } as unknown as Req;
    expect(requireAuth(user).uid).toBe('u1');
    expect(() => requireAdmin(user)).toThrow(expect.objectContaining({ code: 'permission-denied' }));
    const admin = { auth: { uid: 'a1', token: { admin: true } } } as unknown as Req;
    expect(requireAdmin(admin).uid).toBe('a1');
  });

  test('bearerToken and secretsEqual', () => {
    expect(bearerToken('Bearer abc')).toBe('abc');
    expect(bearerToken('bearer   abc ')).toBe('abc');
    expect(bearerToken(['Bearer x'])).toBe('x');
    expect(bearerToken('Basic abc')).toBeUndefined();
    expect(bearerToken(undefined)).toBeUndefined();
    expect(secretsEqual('abc', 'abc')).toBe(true);
    expect(secretsEqual('abc', 'abd')).toBe(false);
    expect(secretsEqual('abc', 'abcd')).toBe(false);
    expect(secretsEqual(undefined, 'abc')).toBe(false);
    expect(secretsEqual('', '')).toBe(false);
  });
});

describe('time helpers', () => {
  test('strict ISO dates', () => {
    expect(parseIsoDate('2026-02-28')).toBe(Date.UTC(2026, 1, 28));
    expect(parseIsoDate('2026-02-30')).toBeUndefined();
    expect(parseIsoDate('2026-13-01')).toBeUndefined();
    expect(parseIsoDate('2026-1-01')).toBeUndefined();
    expect(isoDate(Date.UTC(2026, 9, 30, 23, 59))).toBe('2026-10-30');
    expect(daysBetween('2026-10-30', '2026-11-02')).toBe(3);
    expect(daysBetween('2026-11-02', '2026-10-30')).toBe(-3);
  });
});
