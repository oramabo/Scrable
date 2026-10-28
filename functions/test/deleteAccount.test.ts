import { deleteAccount } from '../src/handlers/deleteAccount';
import { FakeFirestore } from './fakeFirestore';
import { FakeUserAdmin } from './fakes';

describe('deleteAccount', () => {
  test('removes the user document, its subcollections and the auth user, leaving other users intact', async () => {
    const seed: Record<string, Record<string, unknown>> = {
      'users/u1': { wallet: { balance: 10 } },
      'users/u1/progress/p1': { completed: true },
      'users/u1/ledger/starting_wallet': { amount: 200 },
      'users/u1/daily/he_2026-10-30_easy': { score: 1 },
      'users/u1/claims/earn_login~day~2026-10-30': { count: 1 },
      'users/u2': { wallet: { balance: 5 } },
      'users/u2/progress/p1': { completed: false },
      'leaderboards/he_2026-10-30_easy/entries/u1': { score: 1 },
    };
    for (let i = 0; i < 450; i++) seed[`users/u1/ledger/e${String(i).padStart(4, '0')}`] = { amount: 1 };
    const db = new FakeFirestore(seed);
    const users = new FakeUserAdmin();
    const res = await deleteAccount({ db, users }, 'u1');
    expect(res.deletedDocs).toBe(1 + 1 + 451 + 1 + 1);
    expect([...db.docs.keys()].filter((p) => p.startsWith('users/u1'))).toEqual([]);
    expect(db.get('users/u2')).toEqual({ wallet: { balance: 5 } });
    expect(db.get('users/u2/progress/p1')).toEqual({ completed: false });
    expect(users.deleted).toEqual(['u1']);
  });

  test('works for a user without any Firestore data', async () => {
    const db = new FakeFirestore();
    const users = new FakeUserAdmin();
    await expect(deleteAccount({ db, users }, 'ghost')).resolves.toEqual({ deletedDocs: 0 });
    expect(users.deleted).toEqual(['ghost']);
  });
});
