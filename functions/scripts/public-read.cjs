#!/usr/bin/env node
/**
 * Makes the content bucket world-readable so the app can fetch puzzles and
 * manifests from https://storage.googleapis.com/<bucket>/... (that URL form
 * is governed by IAM, not by storage.rules). The bucket holds only published
 * content: puzzles/, manifests/ and <lang>/images/. Idempotent.
 *
 *   node scripts/public-read.cjs
 *
 * Credentials and project as for publish-content.cjs (GOOGLE_APPLICATION_CREDENTIALS,
 * GCLOUD_PROJECT, STORAGE_BUCKET).
 */
const { initializeApp } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');

const ROLE = 'roles/storage.objectViewer';

async function main() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) throw new Error('set GCLOUD_PROJECT (or FIREBASE_PROJECT) to the Firebase project id');
  const bucketName = process.env.STORAGE_BUCKET || `${projectId}.appspot.com`;
  initializeApp({ projectId, storageBucket: bucketName });
  const bucket = getStorage().bucket(bucketName);

  const [policy] = await bucket.iam.getPolicy({ requestedPolicyVersion: 3 });
  const binding = policy.bindings.find((b) => b.role === ROLE && !b.condition);
  if (binding && binding.members.includes('allUsers')) {
    console.log(`gs://${bucketName} is already publicly readable`);
    return;
  }
  if (binding) binding.members.push('allUsers');
  else policy.bindings.push({ role: ROLE, members: ['allUsers'] });
  await bucket.iam.setPolicy(policy);
  console.log(`gs://${bucketName}: granted ${ROLE} to allUsers`);
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  console.error(
    'Could not make the bucket public. In the Google Cloud console open Cloud Storage → Buckets → the bucket → Permissions,\n' +
      'turn off "Prevent public access" if it is on, then Grant access: principal allUsers, role Storage Object Viewer.',
  );
  process.exit(1);
});
