const admin = require('firebase-admin');

// Initialize with default credentials (uses GOOGLE_APPLICATION_CREDENTIALS or gcloud auth)
admin.initializeApp({ projectId: 'navigate-native' });
const db = admin.firestore();

const KEEP_USER = '6868383';
const BATCH_SIZE = 400;

async function deleteCollection(collectionPath, filter) {
  const collRef = db.collection(collectionPath);
  let query = collRef.limit(BATCH_SIZE);

  let totalDeleted = 0;
  while (true) {
    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    let count = 0;
    for (const doc of snapshot.docs) {
      if (filter && !filter(doc)) continue;
      batch.delete(doc.ref);
      count++;
    }
    if (count > 0) {
      await batch.commit();
      totalDeleted += count;
      console.log(`  Deleted ${totalDeleted} from ${collectionPath}...`);
    }
    if (snapshot.docs.length < BATCH_SIZE) break;
  }
  return totalDeleted;
}

async function deleteSubcollections(parentCollection, subcollections) {
  const parentSnap = await db.collection(parentCollection).get();
  let total = 0;
  for (const parentDoc of parentSnap.docs) {
    for (const sub of subcollections) {
      const subPath = `${parentCollection}/${parentDoc.id}/${sub}`;
      const subSnap = await db.collection(subPath).get();
      if (subSnap.empty) continue;
      const batch = db.batch();
      for (const doc of subSnap.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      total += subSnap.size;
      console.log(`  Deleted ${subSnap.size} from ${subPath}`);
    }
  }
  return total;
}

async function main() {
  console.log('=== Firestore Cleanup ===');
  console.log(`Keeping user: ${KEEP_USER}`);
  console.log('Keeping: areas + layers\n');

  // 1. Delete navigation subcollections first
  console.log('1. Deleting navigation subcollections...');
  await deleteSubcollections('navigations', [
    'routes', 'tracks', 'punches', 'alerts', 'violations',
    'scores', 'extension_requests',
    'nav_layers_nz', 'nav_layers_nb', 'nav_layers_gg', 'nav_layers_ba'
  ]);

  // 2. Delete navigations
  console.log('\n2. Deleting navigations...');
  const navCount = await deleteCollection('navigations');
  console.log(`  Total navigations deleted: ${navCount}`);

  // 3. Delete navigation_tracks
  console.log('\n3. Deleting navigation_tracks...');
  const trackCount = await deleteCollection('navigation_tracks');
  console.log(`  Total tracks deleted: ${trackCount}`);

  // 4. Delete rooms + messages subcollection
  console.log('\n4. Deleting rooms (PTT)...');
  await deleteSubcollections('rooms', ['messages']);
  const roomCount = await deleteCollection('rooms');
  console.log(`  Total rooms deleted: ${roomCount}`);

  // 5. Delete users (except KEEP_USER)
  console.log(`\n5. Deleting users (keeping ${KEEP_USER})...`);
  const userCount = await deleteCollection('users', (doc) => doc.id !== KEEP_USER);
  console.log(`  Total users deleted: ${userCount}`);

  // 6. Delete units
  console.log('\n6. Deleting units...');
  const unitCount = await deleteCollection('units');
  console.log(`  Total units deleted: ${unitCount}`);

  // 7. Delete navigator_trees
  console.log('\n7. Deleting navigator_trees...');
  const treeCount = await deleteCollection('navigator_trees');
  console.log(`  Total trees deleted: ${treeCount}`);

  // 8. Delete auth_mapping (except KEEP_USER's)
  console.log('\n8. Deleting auth_mapping...');
  const authCount = await deleteCollection('auth_mapping', (doc) => {
    const data = doc.data();
    return data.appUid !== KEEP_USER;
  });
  console.log(`  Total auth_mapping deleted: ${authCount}`);

  // 9. Delete sync_metadata
  console.log('\n9. Deleting sync_metadata...');
  const syncCount = await deleteCollection('sync_metadata');
  console.log(`  Total sync_metadata deleted: ${syncCount}`);

  // 10. Delete navigation_approval (legacy)
  console.log('\n10. Deleting navigation_approval...');
  const approvalCount = await deleteCollection('navigation_approval');
  console.log(`  Total navigation_approval deleted: ${approvalCount}`);

  console.log('\n=== Done! ===');
  console.log('Remaining: areas + layers + user 6868383');
  process.exit(0);
}

main().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
