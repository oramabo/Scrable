import { claimUsername } from '../src/handlers/claimUsername';
import { deleteAccount } from '../src/handlers/deleteAccount';
import { displayNameOf, usernameKey, usernameProblem } from '../src/lib/username';
import { FakeFirestore } from './fakeFirestore';
import { FakeUserAdmin } from './fakes';
import { NOW } from './helpers';

describe('username rules', () => {
  test('accepts Hebrew and Latin letters, digits and inner _ or .', () => {
    for (const ok of ['dana', 'דנה_לוי', 'Puzzler99', 'a.b_c', 'חץ2026']) expect(usernameProblem(ok)).toBeUndefined();
  });

  test('rejects bad lengths, characters and reserved names', () => {
    expect(usernameProblem('ab')).toBe('length');
    expect(usernameProblem('x'.repeat(21))).toBe('length');
    for (const bad of ['_dana', 'dana.', 'da..na', 'da na', 'דָּנָה', 'dana!', 'émile']) expect(usernameProblem(bad)).toBe('characters');
    for (const reserved of ['Admin', 'ad.min', 'CHETZ', 'מנהל']) expect(usernameProblem(reserved)).toBe('reserved');
  });

  test('the uniqueness key ignores case, final letters and separators', () => {
    expect(usernameKey('Dana_Levi')).toBe(usernameKey('dana.levi'));
    expect(usernameKey('שלום')).toBe(usernameKey('שלומ'));
  });

  test('other players see the claimed username before the free-text name', () => {
    expect(displayNameOf({ data: { username: 'dana', profile: { displayName: 'Someone Else' } } })).toBe('dana');
    expect(displayNameOf({ data: { profile: { displayName: ' Free text ' } } })).toBe('Free text');
    expect(displayNameOf({ data: undefined })).toBe('Player');
  });
});

describe('claimUsername', () => {
  /** u1 has linked Google, u3 is still anonymous. */
  function usersWith(): FakeUserAdmin {
    const users = new FakeUserAdmin();
    users.providers['u1'] = ['google.com'];
    return users;
  }

  test('reserves the name and writes it to the user document', async () => {
    const db = new FakeFirestore({ 'users/u1': { profile: { displayName: 'old' } } });
    await expect(claimUsername({ db, users: usersWith() }, 'u1', { username: ' Dana_Levi ' }, NOW)).resolves.toEqual({ username: 'Dana_Levi' });
    expect(db.get('usernames/danalevi')).toEqual({ uid: 'u1', username: 'Dana_Levi', updatedAt: NOW });
    expect(db.get('users/u1')).toMatchObject({ username: 'Dana_Levi', profile: { displayName: 'Dana_Levi' } });
  });

  test('a name taken by someone else (in any spelling) is refused', async () => {
    const db = new FakeFirestore({ 'usernames/danalevi': { uid: 'u2', username: 'dana.levi' } });
    await expect(claimUsername({ db, users: usersWith() }, 'u1', { username: 'DANA_LEVI' }, NOW)).rejects.toMatchObject({ code: 'already-exists', details: { reason: 'taken' } });
    expect(db.get('users/u1')).toBeUndefined();
  });

  test('renaming releases the previous name; re-claiming your own name is fine', async () => {
    const db = new FakeFirestore({ 'users/u1': { username: 'first' }, 'usernames/first': { uid: 'u1', username: 'first' } });
    await claimUsername({ db, users: usersWith() }, 'u1', { username: 'second' }, NOW);
    expect(db.get('usernames/first')).toBeUndefined();
    expect(db.get('usernames/second')).toMatchObject({ uid: 'u1' });
    await expect(claimUsername({ db, users: usersWith() }, 'u1', { username: 'Second' }, NOW)).resolves.toEqual({ username: 'Second' });
  });

  test('anonymous accounts and invalid names are refused', async () => {
    const db = new FakeFirestore();
    await expect(claimUsername({ db, users: usersWith() }, 'u3', { username: 'dana' }, NOW)).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(claimUsername({ db, users: usersWith() }, 'u1', { username: 'a b' }, NOW)).rejects.toMatchObject({ code: 'invalid-argument', details: { reason: 'characters' } });
    await expect(claimUsername({ db, users: usersWith() }, 'u1', {}, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('deleting the account frees the name', async () => {
    const db = new FakeFirestore({ 'users/u1': { username: 'dana' }, 'usernames/dana': { uid: 'u1', username: 'dana' } });
    await deleteAccount({ db, users: new FakeUserAdmin() }, 'u1');
    expect(db.get('usernames/dana')).toBeUndefined();
  });
});
