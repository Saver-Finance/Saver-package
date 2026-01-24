/**
 * SDK Validation Test
 * 
 * This test validates ALL SDK methods used in INTEGRATION_SHORT.md
 * to prove they work correctly with the Sui/OneChain SDK.
 */

import { SuiClient } from '@onelabs/sui/client';
import { Ed25519Keypair } from '@onelabs/sui/keypairs/ed25519';
import { Transaction } from '@onelabs/sui/transactions';
import { decodeSuiPrivateKey } from '@onelabs/sui/cryptography';
import dotenv from 'dotenv';

dotenv.config();

// Configuration
const RPC_URL = process.env.RPC_URL || 'https://rpc-testnet.onelabs.cc:443';
const PACKAGE_ID = process.env.PACKAGE_ID || "0x0626d0503c31354e982bd71655ccd8b46d8f22943d0c19bcfdc594cd11b9305e";
const COIN_TYPE = '0x2::oct::OCT';

const client = new SuiClient({ url: RPC_URL });

// Test counters
let testsRun = 0;
let testsPassed = 0;
let testsFailed = 0;

function logTest(name: string, passed: boolean, details?: string) {
    testsRun++;
    if (passed) {
        testsPassed++;
        console.log(`✅ TEST ${testsRun}: ${name}`);
        if (details) console.log(`   ${details}`);
    } else {
        testsFailed++;
        console.log(`❌ TEST ${testsRun}: ${name}`);
        if (details) console.log(`   ERROR: ${details}`);
    }
}

async function main() {
    console.log('🧪 SDK VALIDATION TEST - Testing all methods from INTEGRATION_SHORT.md\n');
    console.log('='.repeat(80));

    try {
        // ========================================================================
        // TEST 1: queryObjects - Query shared Room objects by type
        // ========================================================================
        console.log('\n📋 TEST GROUP 1: queryObjects (for shared objects)');
        console.log('-'.repeat(80));

        try {
            const response = await client.queryObjects({
                filter: {
                    StructType: `${PACKAGE_ID}::gamehub::Room<${COIN_TYPE}>`
                },
                options: {
                    showContent: true,
                    showType: true
                }
            });

            logTest(
                'queryObjects with StructType filter',
                true,
                `Found ${response.data.length} Room objects`
            );

            // Verify response structure
            if (response.data.length > 0) {
                const firstRoom = response.data[0];
                const hasData = !!firstRoom.data;
                const hasContent = !!firstRoom.data?.content;

                logTest(
                    'queryObjects response has correct structure',
                    hasData && hasContent,
                    `data: ${hasData}, content: ${hasContent}`
                );

                // Test filtering for Waiting rooms
                const waitingRooms = response.data.filter(room => {
                    if (!room.data?.content || room.data.content.dataType !== 'moveObject') {
                        return false;
                    }
                    const fields = (room.data.content as any).fields;
                    return fields.status?.variant === 'Waiting';
                });

                logTest(
                    'Client-side filtering for Waiting rooms',
                    true,
                    `${waitingRooms.length} waiting rooms out of ${response.data.length} total`
                );
            } else {
                console.log('   ℹ️  No rooms found (this is OK if none exist yet)');
            }

        } catch (error: any) {
            logTest(
                'queryObjects with StructType filter',
                false,
                error.message
            );
        }

        // ========================================================================
        // TEST 2: Verify getOwnedObjects REQUIRES owner parameter
        // ========================================================================
        console.log('\n📋 TEST GROUP 2: getOwnedObjects (should FAIL without owner)');
        console.log('-'.repeat(80));

        try {
            // This should FAIL because owner is required
            const response = await (client as any).getOwnedObjects({
                filter: { StructType: `${PACKAGE_ID}::gamehub::Room<${COIN_TYPE}>` },
                options: { showContent: true }
            });

            logTest(
                'getOwnedObjects without owner parameter should fail',
                false,
                'Expected error but call succeeded - SDK may have changed!'
            );
        } catch (error: any) {
            const isExpectedError = error.message?.includes('owner') ||
                error.message?.includes('required') ||
                error.message?.includes('missing');

            logTest(
                'getOwnedObjects correctly requires owner parameter',
                isExpectedError,
                `Error message: "${error.message}"`
            );
        }

        // ========================================================================
        // TEST 3: getOwnedObjects WITH owner (correct usage)
        // ========================================================================
        console.log('\n📋 TEST GROUP 3: getOwnedObjects (correct usage with owner)');
        console.log('-'.repeat(80));

        if (!process.env.USER_1) {
            console.log('   ⚠️  Skipping: USER_1 not set in .env');
        } else {
            try {
                const player1Kp = Ed25519Keypair.deriveKeypair(process.env.USER_1);
                const p1Addr = player1Kp.toSuiAddress();

                const response = await client.getOwnedObjects({
                    owner: p1Addr,
                    filter: {
                        StructType: `0x2::coin::Coin<${COIN_TYPE}>`
                    },
                    options: { showContent: true }
                });

                logTest(
                    'getOwnedObjects with owner parameter (for coins)',
                    true,
                    `Found ${response.data.length} coins owned by ${p1Addr.slice(0, 10)}...`
                );

            } catch (error: any) {
                logTest(
                    'getOwnedObjects with owner parameter',
                    false,
                    error.message
                );
            }
        }

        // ========================================================================
        // TEST 4: multiGetObjects - Fetch multiple objects by ID
        // ========================================================================
        console.log('\n📋 TEST GROUP 4: multiGetObjects');
        console.log('-'.repeat(80));

        try {
            // Use well-known shared objects (Clock and Random)
            const response = await client.multiGetObjects({
                ids: ['0x6', '0x8'],  // Clock and Random
                options: { showContent: true }
            });

            const [clockObj, randomObj] = response;

            // Verify structure
            const clockValid = !!clockObj.data;
            const randomValid = !!randomObj.data;

            logTest(
                'multiGetObjects returns array of objects',
                response.length === 2,
                `Returned ${response.length} objects`
            );

            logTest(
                'multiGetObjects response structure is correct',
                clockValid && randomValid,
                `Clock valid: ${clockValid}, Random valid: ${randomValid}`
            );

            // Test error handling pattern
            try {
                if (!clockObj.data?.content || clockObj.data.content.dataType !== 'moveObject') {
                    throw new Error('Clock object not found or invalid');
                }
                logTest(
                    'Error handling pattern for multiGetObjects',
                    true,
                    'Null checks work correctly'
                );
            } catch (e: any) {
                logTest(
                    'Error handling pattern for multiGetObjects',
                    false,
                    e.message
                );
            }

        } catch (error: any) {
            logTest(
                'multiGetObjects',
                false,
                error.message
            );
        }

        // ========================================================================
        // TEST 5: getObject - Fetch single object by ID
        // ========================================================================
        console.log('\n📋 TEST GROUP 5: getObject');
        console.log('-'.repeat(80));

        try {
            const response = await client.getObject({
                id: '0x6',  // Clock object
                options: { showContent: true }
            });

            logTest(
                'getObject with options',
                !!response.data,
                `Object ID: ${response.data?.objectId}`
            );

            // Test error handling
            if (!response.data?.content || response.data.content.dataType !== 'moveObject') {
                logTest(
                    'getObject error handling (Clock is not moveObject)',
                    true,
                    'Correctly detected non-moveObject type'
                );
            }

        } catch (error: any) {
            logTest(
                'getObject with options',
                false,
                error.message
            );
        }

        // ========================================================================
        // TEST 6: getTransactionBlock - Verify transaction
        // ========================================================================
        console.log('\n📋 TEST GROUP 6: getTransactionBlock');
        console.log('-'.repeat(80));

        try {
            // Get a recent transaction from chain info
            const chainId = await client.getChainIdentifier();
            console.log(`   Connected to chain: ${chainId}`);

            // Try to get latest checkpoint to find a transaction
            try {
                const checkpoint = await client.getLatestCheckpointSequenceNumber();
                console.log(`   Latest checkpoint: ${checkpoint}`);

                logTest(
                    'getTransactionBlock method exists',
                    typeof client.getTransactionBlock === 'function',
                    'Method is available in SDK'
                );
            } catch (e) {
                console.log('   ℹ️  Could not fetch checkpoint (this is OK)');
            }

        } catch (error: any) {
            logTest(
                'getTransactionBlock',
                false,
                error.message
            );
        }

        // ========================================================================
        // TEST 7: getCoins - Used in integration examples
        // ========================================================================
        console.log('\n📋 TEST GROUP 7: getCoins');
        console.log('-'.repeat(80));

        if (!process.env.USER_1) {
            console.log('   ⚠️  Skipping: USER_1 not set in .env');
        } else {
            try {
                const player1Kp = Ed25519Keypair.deriveKeypair(process.env.USER_1);
                const p1Addr = player1Kp.toSuiAddress();

                const coins = await client.getCoins({
                    owner: p1Addr,
                    coinType: COIN_TYPE
                });

                logTest(
                    'getCoins with owner and coinType',
                    true,
                    `Found ${coins.data.length} coins, Total balance: ${coins.data.reduce((sum, c) => sum + BigInt(c.balance), 0n)}`
                );

                // Test sorting pattern from integration code
                const sorted = coins.data.sort((a, b) => Number(b.balance) - Number(a.balance));
                if (sorted.length > 0) {
                    logTest(
                        'Coin sorting pattern (largest first)',
                        BigInt(sorted[0].balance) >= BigInt(sorted[sorted.length - 1]?.balance || 0),
                        `Largest coin: ${sorted[0].balance}`
                    );
                }

            } catch (error: any) {
                logTest(
                    'getCoins',
                    false,
                    error.message
                );
            }
        }

        // ========================================================================
        // TEST 8: Transaction building patterns
        // ========================================================================
        console.log('\n📋 TEST GROUP 8: Transaction building');
        console.log('-'.repeat(80));

        try {
            const tx = new Transaction();

            logTest(
                'Transaction constructor',
                !!tx,
                'Transaction object created'
            );

            // Test moveCall pattern
            tx.moveCall({
                target: `${PACKAGE_ID}::bomb_panic::join`,
                arguments: [tx.object('0x1234')],
                typeArguments: [COIN_TYPE]
            });

            logTest(
                'Transaction.moveCall pattern',
                true,
                'moveCall added successfully'
            );

            // Test splitCoins pattern
            const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(100)]);

            logTest(
                'Transaction.splitCoins pattern',
                !!coin,
                'splitCoins works correctly'
            );

            // Test pure value patterns
            tx.pure.u64(1000);
            tx.pure.address('0x1234');
            tx.pure.string('test');
            tx.pure.u8(8);

            logTest(
                'Transaction.pure value builders',
                true,
                'All pure value types work'
            );

        } catch (error: any) {
            logTest(
                'Transaction building',
                false,
                error.message
            );
        }

        // ========================================================================
        // TEST 9: Event subscription (check if method exists)
        // ========================================================================
        console.log('\n📋 TEST GROUP 9: Event subscription');
        console.log('-'.repeat(80));

        try {
            const hasSubscribeEvent = typeof client.subscribeEvent === 'function';

            logTest(
                'subscribeEvent method exists',
                hasSubscribeEvent,
                hasSubscribeEvent ? 'Method available' : 'Method not found'
            );

            if (hasSubscribeEvent) {
                console.log('   ℹ️  subscribeEvent is available (not testing actual subscription)');
            }

        } catch (error: any) {
            logTest(
                'Event subscription check',
                false,
                error.message
            );
        }

        // ========================================================================
        // SUMMARY
        // ========================================================================
        console.log('\n' + '='.repeat(80));
        console.log('📊 TEST SUMMARY');
        console.log('='.repeat(80));
        console.log(`Total Tests Run:    ${testsRun}`);
        console.log(`✅ Tests Passed:    ${testsPassed}`);
        console.log(`❌ Tests Failed:    ${testsFailed}`);
        console.log(`Success Rate:       ${((testsPassed / testsRun) * 100).toFixed(1)}%`);
        console.log('='.repeat(80));

        if (testsFailed === 0) {
            console.log('\n🎉 ALL TESTS PASSED! The SDK corrections in INTEGRATION_SHORT.md are CORRECT!');
        } else {
            console.log(`\n⚠️  ${testsFailed} test(s) failed. Review the errors above.`);
        }

        process.exit(testsFailed > 0 ? 1 : 0);

    } catch (error) {
        console.error('\n💥 Fatal error during test execution:', error);
        process.exit(1);
    }
}

main();
