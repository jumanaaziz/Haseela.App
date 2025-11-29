import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/child_options.dart';
import '../../models/wallet.dart';
import '../../models/transaction.dart' as app_transaction;
import '../services/firebase_service.dart';

class ChildProfileViewScreen extends StatefulWidget {
  final ChildOption child;
  final String parentId;

  const ChildProfileViewScreen({
    super.key,
    required this.child,
    required this.parentId,
  });

  @override
  State<ChildProfileViewScreen> createState() => _ChildProfileViewScreenState();
}

class _ChildProfileViewScreenState extends State<ChildProfileViewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _childDetails;
  Wallet? _childWallet;
  List<app_transaction.Transaction> _childTransactions = [];
  bool _isLoadingWallet = true;
  StreamSubscription<QuerySnapshot>? _walletSubscription;
  StreamSubscription<QuerySnapshot>? _transactionSubscription;

  // PIN visibility state
  bool _isPinVisible = false;
  Timer? _pinAutoMaskTimer;
  String? _plainPin; // Temporary storage for plaintext PIN

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Debug child information
    print('=== CHILD OBJECT DEBUG ===');
    print('Child ID: ${widget.child.id}');
    print('Child First Name: ${widget.child.firstName}');
    print('Child Username: ${widget.child.username}');
    print('Child Email: ${widget.child.email}');
    print('Child ID Type: ${widget.child.id.runtimeType}');
    print('Child ID Length: ${widget.child.id.length}');
    print('========================');

    // Set data immediately in initState
    _childDetails = {
      'firstName': widget.child.firstName,
      'username': widget.child.username,
      'email': widget.child.email ?? 'N/A',
      'pin_display': '123456', // Default PIN for now
    };

    // Set plain PIN for demonstration (in real app, this would come from secure storage)
    _plainPin = '123456';

    // Test Firebase connection first
    _testFirebaseConnection();

    // Try to load wallet001 directly first
    _loadWallet001Directly();

    // Load wallet data
    _loadChildWallet();

    // Also try to load from Firestore in the background
    _loadFromFirestoreInBackground();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _walletSubscription?.cancel();
    _transactionSubscription?.cancel();
    _pinAutoMaskTimer?.cancel();
    super.dispose();
  }

  void _testFirebaseConnection() {
    print('=== TESTING FIREBASE CONNECTION ===');
    FirebaseFirestore.instance
        .collection("Wallets")
        .limit(1)
        .get()
        .then((QuerySnapshot snapshot) {
          print('=== FIREBASE CONNECTION SUCCESS ===');
          print(
            'Found ${snapshot.docs.length} documents in Wallets collection',
          );
          if (snapshot.docs.isNotEmpty) {
            print('Sample document: ${snapshot.docs.first.data()}');
          }
        })
        .catchError((error) {
          print('=== FIREBASE CONNECTION ERROR: $error ===');
        });
  }

  void _loadWallet001Directly() {
    print('=== FETCHING CHILD WALLET INFO ===');
    print('Parent ID: ${widget.parentId}');
    print('Child ID: ${widget.child.id}');

    // Set a timeout to ensure loading state is cleared
    Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoadingWallet) {
        print('=== WALLET LOADING TIMEOUT - SHOWING DEFAULT VALUES ===');
        setState(() {
          _isLoadingWallet = false;
        });
      }
    });

    // Use the correct Firebase path: Parents/{parentId}/Children/{childId}/Wallet/wallet001
    FirebaseFirestore.instance
        .collection("Parents")
        .doc(widget.parentId)
        .collection("Children")
        .doc(widget.child.id)
        .collection("Wallet")
        .doc("wallet001")
        .get()
        .then((DocumentSnapshot doc) {
          print('=== DOCUMENT EXISTS: ${doc.exists} ===');
          print(
            '📘 CHILD PROFILE DEBUG - ParentID: ${widget.parentId} | ChildID: ${widget.child.id}',
          );

          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>?;
            print('=== WALLET FOUND ===');
            print('Document ID: ${doc.id}');
            print('Document data: $data');
            print('Total Balance: ${data?['totalBalance']}');
            print('Spending: ${data?['spendingBalance']}');
            print('Savings: ${data?['savingBalance']}');
            print('Goal: ${data?['savingGoal']}');

            try {
              final wallet = Wallet.fromMap(data!);
              print('=== WALLET PARSED SUCCESSFULLY ===');
              print('Wallet totalBalance: ${wallet.totalBalance}');
              print('Wallet spendingBalance: ${wallet.spendingBalance}');
              print('Wallet savingBalance: ${wallet.savingBalance}');

              if (mounted) {
                setState(() {
                  _childWallet = wallet;
                  _isLoadingWallet = false;
                });
                print('=== WALLET LOADED SUCCESSFULLY ===');
              }
            } catch (e) {
              print('=== ERROR PARSING WALLET: $e ===');
              if (mounted) {
                setState(() {
                  _isLoadingWallet = false;
                });
              }
            }
          } else {
            print('=== NO WALLET FOUND ===');
            print(
              'Path checked: Parents/${widget.parentId}/Children/${widget.child.id}/Wallet/wallet001',
            );
            if (mounted) {
              setState(() {
                _isLoadingWallet = false;
              });
            }
          }
        })
        .catchError((error) {
          print('=== FIREBASE ERROR: $error ===');
          if (mounted) {
            setState(() {
              _isLoadingWallet = false;
            });
          }
        });
  }

  void _tryAlternativeQueries() {
    print('=== TRYING ALTERNATIVE QUERIES ===');

    // Try different field names
    final alternativeFields = ['childId', 'child_id', 'user_id', 'id'];

    for (String field in alternativeFields) {
      FirebaseFirestore.instance
          .collection("Wallets")
          .where(field, isEqualTo: widget.child.id)
          .get()
          .then((QuerySnapshot snapshot) {
            if (snapshot.docs.isNotEmpty) {
              print('=== FOUND WALLET WITH FIELD: $field ===');
              print('Found ${snapshot.docs.length} documents');
              final doc = snapshot.docs.first;
              print('Document data: ${doc.data()}');

              // Try to load this wallet
              try {
                final wallet = Wallet.fromFirestore(
                  doc as DocumentSnapshot<Map<String, dynamic>>,
                  null,
                );
                if (mounted) {
                  setState(() {
                    _childWallet = wallet;
                    _isLoadingWallet = false;
                  });
                }
                print('=== SUCCESSFULLY LOADED WALLET WITH FIELD: $field ===');
              } catch (e) {
                print('=== ERROR PARSING WALLET WITH FIELD $field: $e ===');
              }
            } else {
              print('=== NO WALLET FOUND WITH FIELD: $field ===');
            }
          })
          .catchError((error) {
            print('=== ERROR QUERYING FIELD $field: $error ===');
          });
    }

    // Also try to get wallet by document ID
    FirebaseFirestore.instance
        .collection("Wallets")
        .doc(widget.child.id)
        .get()
        .then((DocumentSnapshot doc) {
          if (doc.exists) {
            print('=== FOUND WALLET BY DOCUMENT ID ===');
            print('Document data: ${doc.data()}');

            try {
              final wallet = Wallet.fromFirestore(
                doc as DocumentSnapshot<Map<String, dynamic>>,
                null,
              );
              if (mounted) {
                setState(() {
                  _childWallet = wallet;
                  _isLoadingWallet = false;
                });
              }
              print('=== SUCCESSFULLY LOADED WALLET BY DOCUMENT ID ===');
            } catch (e) {
              print('=== ERROR PARSING WALLET BY DOCUMENT ID: $e ===');
            }
          } else {
            print('=== NO WALLET FOUND BY DOCUMENT ID ===');
          }
        })
        .catchError((error) {
          print('=== ERROR QUERYING BY DOCUMENT ID: $error ===');
        });

    // Try to find wallet by email or other child info
    _tryFindWalletByChildInfo();
  }

  Future<void> _createWallet() async {
    try {
      print('🔧 Creating wallet for child: ${widget.child.id}');

      // Create a default wallet
      final wallet = Wallet(
        id: 'wallet001',
        userId: widget.child.id,
        totalBalance: 0.0,
        spendingBalance: 0.0,
        savingBalance: 0.0,
        savingGoal: 100.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Try to create wallet using FirebaseService
      final success = await FirebaseService.createChildWallet(
        widget.parentId,
        widget.child.id,
        wallet,
      );

      if (success) {
        print('✅ Wallet created successfully via FirebaseService.');
        // Refresh the wallet data
        _loadWallet001Directly();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Wallet created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ Failed to create wallet via FirebaseService.');
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create wallet. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error creating wallet: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating wallet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _tryFindWalletByChildInfo() {
    print('=== TRYING TO FIND WALLET BY CHILD INFO ===');

    // Try to find wallet by email
    if (widget.child.email != null && widget.child.email!.isNotEmpty) {
      print('=== SEARCHING BY EMAIL: ${widget.child.email} ===');

      // First, let's get all wallets and check if any have matching email
      FirebaseFirestore.instance
          .collection("Wallets")
          .get()
          .then((QuerySnapshot allWallets) {
            for (var doc in allWallets.docs) {
              final data = doc.data() as Map<String, dynamic>?;
              print('Checking wallet ${doc.id}:');
              print('  - userId: ${data?['userId']}');
              print('  - email: ${data?['email']}');
              print('  - childEmail: ${data?['childEmail']}');
              print('  - All fields: ${data?.keys.toList()}');

              // Check if this wallet belongs to this child by email
              if (data?['email'] == widget.child.email ||
                  data?['childEmail'] == widget.child.email) {
                print('=== FOUND WALLET BY EMAIL MATCH ===');
                print('Wallet ID: ${doc.id}');
                print('Wallet data: ${data}');

                try {
                  final wallet = Wallet.fromFirestore(
                    doc as DocumentSnapshot<Map<String, dynamic>>,
                    null,
                  );
                  if (mounted) {
                    setState(() {
                      _childWallet = wallet;
                      _isLoadingWallet = false;
                    });
                  }
                  print('=== SUCCESSFULLY LOADED WALLET BY EMAIL ===');
                  return; // Exit early if found
                } catch (e) {
                  print('=== ERROR PARSING WALLET BY EMAIL: $e ===');
                }
              }
            }
            print('=== NO WALLET FOUND BY EMAIL ===');
          })
          .catchError((error) {
            print('=== ERROR SEARCHING BY EMAIL: $error ===');
          });
    }
  }

  void _linkWalletToChild() {
    print('=== LINKING WALLET TO CHILD ===');
    print('Child ID: ${widget.child.id}');
    print('Child Email: ${widget.child.email}');

    // First, let's find the wallet by its document ID "wallet001"
    FirebaseFirestore.instance
        .collection("Wallets")
        .doc("wallet001")
        .get()
        .then((DocumentSnapshot doc) {
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>?;
            print('=== FOUND WALLET001 ===');
            print('Current userId: ${data?['userId']}');
            print('Wallet data: ${data}');

            // Update the wallet's userId to match the child's ID
            doc.reference
                .update({
                  'userId': widget.child.id,
                  'childId': widget.child.id,
                  'email': widget.child.email,
                  'updatedAt': DateTime.now().toIso8601String(),
                })
                .then((_) {
                  print('=== WALLET SUCCESSFULLY LINKED TO CHILD ===');
                  print('Updated userId to: ${widget.child.id}');

                  // Reload the wallet data
                  _loadChildWallet();
                })
                .catchError((error) {
                  print('=== ERROR LINKING WALLET: $error ===');
                });
          } else {
            print('=== WALLET001 NOT FOUND ===');

            // Fallback: search by email
            FirebaseFirestore.instance
                .collection("Wallets")
                .get()
                .then((QuerySnapshot allWallets) {
                  for (var doc in allWallets.docs) {
                    final data = doc.data() as Map<String, dynamic>?;
                    print('Checking wallet ${doc.id}:');
                    print('  - userId: ${data?['userId']}');
                    print('  - email: ${data?['email']}');
                    print('  - All fields: ${data?.keys.toList()}');

                    // Check if this wallet belongs to this child by email
                    if (data?['email'] == widget.child.email ||
                        data?['childEmail'] == widget.child.email) {
                      print('=== FOUND WALLET TO LINK: ${doc.id} ===');
                      print('Current userId: ${data?['userId']}');

                      // Update the wallet's userId to match the child's ID
                      doc.reference
                          .update({
                            'userId': widget.child.id,
                            'childId': widget.child.id,
                            'email': widget.child.email,
                            'updatedAt': DateTime.now().toIso8601String(),
                          })
                          .then((_) {
                            print(
                              '=== WALLET SUCCESSFULLY LINKED TO CHILD ===',
                            );
                            print('Updated userId to: ${widget.child.id}');

                            // Reload the wallet data
                            _loadChildWallet();
                          })
                          .catchError((error) {
                            print('=== ERROR LINKING WALLET: $error ===');
                          });
                      return;
                    }
                  }
                  print('=== NO WALLET FOUND TO LINK ===');
                })
                .catchError((error) {
                  print('=== ERROR SEARCHING FOR WALLET TO LINK: $error ===');
                });
          }
        })
        .catchError((error) {
          print('=== ERROR GETTING WALLET001: $error ===');
        });
  }

  void _loadChildWallet() {
    print('=== FETCHING CHILD WALLET ===');

    // Simply fetch wallet001 directly
    _loadWallet001Directly();
  }

  void _loadChildTransactions() {
    print('=== LOADING TRANSACTIONS FOR CHILD: ${widget.child.id} ===');

    _transactionSubscription = FirebaseFirestore.instance
        .collection("Transactions")
        .where("userId", isEqualTo: widget.child.id)
        .orderBy("date", descending: true)
        .limit(10)
        .snapshots()
        .listen(
          (QuerySnapshot snapshot) {
            print(
              '=== TRANSACTIONS QUERY RESULT: ${snapshot.docs.length} transactions found ===',
            );

            final transactions = snapshot.docs
                .map(
                  (doc) => app_transaction.Transaction.fromMap(
                    doc.data() as Map<String, dynamic>,
                  ),
                )
                .toList();

            if (mounted) {
              setState(() {
                _childTransactions = transactions;
              });
            }

            print(
              '=== TRANSACTIONS LOADED: ${transactions.length} transactions ===',
            );
          },
          onError: (error) {
            print('=== ERROR LOADING TRANSACTIONS: $error ===');
          },
        );
  }

  Future<void> _loadFromFirestoreInBackground() async {
    try {
      print('=== LOADING FROM FIRESTORE IN BACKGROUND ===');
      final doc = await FirebaseFirestore.instance
          .collection('Parents')
          .doc(widget.parentId)
          .collection('Children')
          .doc(widget.child.id)
          .get()
          .timeout(const Duration(seconds: 5));

      if (doc.exists) {
        final data = doc.data();
        print('Firestore data found: $data');

        if (data != null &&
            data['firstName'] != null &&
            data['firstName'].toString().trim().isNotEmpty) {
          if (mounted) {
            setState(() {
              _childDetails = {
                'firstName': data['firstName'] ?? widget.child.firstName,
                'username': data['username'] ?? widget.child.username,
                'email': data['email'] ?? widget.child.email ?? 'N/A',
                'pin_display': data['pin_display'] ?? 'N/A',
              };
            });
            print('=== UPDATED WITH FIRESTORE DATA ===');
          }
        }
      }
    } catch (e) {
      print('Background Firestore load failed: $e');
      // Keep the immediate data we already have
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth >= 600;
    final isDesktop = screenWidth >= 1024;
    final isSmallScreen = screenHeight < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isTablet, isDesktop, isSmallScreen),
            _buildTabBar(isTablet, isDesktop, isSmallScreen),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTrackWalletTab(isTablet, isDesktop, isSmallScreen),
                  _buildAccountInfoTab(isTablet, isDesktop, isSmallScreen),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTablet, bool isDesktop, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop
            ? 24.w
            : isTablet
            ? 20.w
            : 16.w,
        vertical: isDesktop
            ? 20.h
            : isTablet
            ? 16.h
            : isSmallScreen
            ? 12.h
            : 16.h,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF8B5CF6)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: EdgeInsets.all(
                isDesktop
                    ? 12.w
                    : isTablet
                    ? 10.w
                    : isSmallScreen
                    ? 8.w
                    : 10.w,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(
                  isDesktop
                      ? 12.r
                      : isTablet
                      ? 10.r
                      : isSmallScreen
                      ? 8.r
                      : 10.r,
                ),
              ),
              child: Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: isDesktop
                    ? 24.sp
                    : isTablet
                    ? 22.sp
                    : isSmallScreen
                    ? 18.sp
                    : 20.sp,
              ),
            ),
          ),
          SizedBox(
            width: isDesktop
                ? 16.w
                : isTablet
                ? 14.w
                : isSmallScreen
                ? 12.w
                : 14.w,
          ),
          CircleAvatar(
            radius: isDesktop
                ? 30.r
                : isTablet
                ? 28.r
                : isSmallScreen
                ? 20.r
                : 25.r,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: widget.child.avatar != null
                ? ClipOval(
                    child: Image.network(
                      widget.child.avatar!,
                      width:
                          (isDesktop
                              ? 30.r
                              : isTablet
                              ? 28.r
                              : isSmallScreen
                              ? 20.r
                              : 25.r) *
                          2,
                      height:
                          (isDesktop
                              ? 30.r
                              : isTablet
                              ? 28.r
                              : isSmallScreen
                              ? 20.r
                              : 25.r) *
                          2,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) {
                        return Text(
                          widget.child.initial,
                          style: TextStyle(
                            fontSize: isDesktop
                                ? 24.sp
                                : isTablet
                                ? 22.sp
                                : isSmallScreen
                                ? 16.sp
                                : 20.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  )
                : Text(
                    widget.child.initial,
                    style: TextStyle(
                      fontSize: isDesktop
                          ? 24.sp
                          : isTablet
                          ? 22.sp
                          : isSmallScreen
                          ? 16.sp
                          : 20.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
          SizedBox(
            width: isDesktop
                ? 16.w
                : isTablet
                ? 14.w
                : isSmallScreen
                ? 12.w
                : 14.w,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.child.firstName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop
                        ? 24.sp
                        : isTablet
                        ? 22.sp
                        : isSmallScreen
                        ? 18.sp
                        : 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.child.lastName,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: isDesktop
                        ? 16.sp
                        : isTablet
                        ? 15.sp
                        : isSmallScreen
                        ? 12.sp
                        : 14.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isTablet, bool isDesktop, bool isSmallScreen) {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF8B5CF6),
        labelColor: const Color(0xFF8B5CF6),
        unselectedLabelColor: Colors.grey[600],
        labelStyle: TextStyle(
          fontSize: isDesktop
              ? 16.sp
              : isTablet
              ? 15.sp
              : isSmallScreen
              ? 12.sp
              : 14.sp,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: isDesktop
              ? 16.sp
              : isTablet
              ? 15.sp
              : isSmallScreen
              ? 12.sp
              : 14.sp,
          fontWeight: FontWeight.normal,
        ),
        tabs: const [
          Tab(text: 'Track Child Wallet'),
          Tab(text: 'Child Account Information'),
        ],
      ),
    );
  }

  Widget _buildAccountInfoTab(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        isDesktop
            ? 24.w
            : isTablet
            ? 20.w
            : 16.w,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(
              isDesktop
                  ? 24.w
                  : isTablet
                  ? 20.w
                  : 16.w,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                isDesktop
                    ? 16.r
                    : isTablet
                    ? 14.r
                    : isSmallScreen
                    ? 10.r
                    : 12.r,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Information',
                  style: TextStyle(
                    fontSize: isDesktop
                        ? 20.sp
                        : isTablet
                        ? 18.sp
                        : isSmallScreen
                        ? 16.sp
                        : 18.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(
                  height: isDesktop
                      ? 20.h
                      : isTablet
                      ? 16.h
                      : isSmallScreen
                      ? 12.h
                      : 16.h,
                ),
                if (_childDetails != null) ...[
                  _buildInfoRow(
                    'First Name',
                    _childDetails!['firstName'] ?? '',
                    isTablet,
                    isDesktop,
                    isSmallScreen,
                  ),
                  _buildInfoRow(
                    'Username',
                    _childDetails!['username'] ?? '',
                    isTablet,
                    isDesktop,
                    isSmallScreen,
                  ),
                  _buildInfoRow(
                    'Email',
                    _childDetails!['email'] ?? '',
                    isTablet,
                    isDesktop,
                    isSmallScreen,
                  ),
                  _buildPinRow(isTablet, isDesktop, isSmallScreen),
                ] else ...[
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      SizedBox(height: 16.h),
                      Text(
                        'Loading child information...',
                        style: TextStyle(
                          fontSize: isDesktop
                              ? 16.sp
                              : isTablet
                              ? 15.sp
                              : isSmallScreen
                              ? 12.sp
                              : 14.sp,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 8.h),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _childDetails = {
                              'firstName': widget.child.firstName,
                              'username': widget.child.username,
                              'email': widget.child.email ?? 'N/A',
                              'pin_display': '123456',
                            };
                            _plainPin = '123456';
                          });
                        },
                        child: Text(
                          'Retry Now',
                          style: TextStyle(
                            fontSize: isDesktop
                                ? 14.sp
                                : isTablet
                                ? 13.sp
                                : isSmallScreen
                                ? 11.sp
                                : 12.sp,
                            color: const Color(0xFF8B5CF6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackWalletTab(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    if (_isLoadingWallet) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show wallet information - use Firebase data if available, otherwise show default values
    final wallet =
        _childWallet ??
        Wallet(
          id: widget.child.id,
          userId: widget.child.id,
          totalBalance: 0.0,
          spendingBalance: 0.0,
          savingBalance: 0.0,
          savingGoal: 100.0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

    final isDataFromFirebase = _childWallet != null;

    return SingleChildScrollView(
      padding: EdgeInsets.all(
        isDesktop
            ? 24.w
            : isTablet
            ? 20.w
            : 16.w,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Data Source Indicator
          if (!isDataFromFirebase) ...[
            Container(
              padding: EdgeInsets.all(12.w),
              margin: EdgeInsets.only(bottom: 16.h),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange[600],
                        size: 16.sp,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'No wallet data found in Firebase. Showing default values.',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Total Balance Card
          _buildTotalBalanceCard(wallet, isTablet, isDesktop, isSmallScreen),
          SizedBox(height: 20.h),

          // Spending and Savings Cards
          Row(
            children: [
              Expanded(
                child: _buildWalletDetail(
                  'Spending',
                  wallet.spendingBalance,
                  Icons.shopping_cart,
                  const Color(0xFFEF4444),
                  isTablet,
                  isDesktop,
                  isSmallScreen,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildWalletDetail(
                  'Savings',
                  wallet.savingBalance,
                  Icons.savings,
                  const Color(0xFF3B82F6),
                  isTablet,
                  isDesktop,
                  isSmallScreen,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),

          // Saving Goal Progress
          _buildSavingGoalProgress(wallet, isTablet, isDesktop, isSmallScreen),
          SizedBox(height: 20.h),

          // Savings Transactions Section
          _buildSavingsTransactionsSection(isTablet, isDesktop, isSmallScreen),
          SizedBox(height: 20.h),

          // Spending Transactions Section
          _buildSpendingTransactionsSection(isTablet, isDesktop, isSmallScreen),
          SizedBox(height: 20.h),

          // Recent Transactions
          if (_childTransactions.isNotEmpty) ...[
            Text(
              'Recent Transactions',
              style: TextStyle(
                fontSize: isDesktop
                    ? 18.sp
                    : isTablet
                    ? 16.sp
                    : isSmallScreen
                    ? 14.sp
                    : 15.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 12.h),
            ..._childTransactions
                .take(5)
                .map(
                  (transaction) => _buildTransactionItem(
                    transaction,
                    isTablet,
                    isDesktop,
                    isSmallScreen,
                  ),
                ),
          ],
        ],
      ),
    );
  }

  /// Toggle PIN visibility
  void _togglePinVisibility() {
    setState(() {
      _isPinVisible = !_isPinVisible;
    });

    // Cancel existing timer if any
    _pinAutoMaskTimer?.cancel();

    // If PIN is now visible, start auto-mask timer
    if (_isPinVisible) {
      _pinAutoMaskTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _isPinVisible = false;
          });
        }
      });
    }
  }

  /// Check if PIN can be revealed (not hashed)
  bool _canRevealPin() {
    // In a real app, this would check if the PIN is stored in plaintext
    // vs hashed. For now, we assume it can be revealed if _plainPin exists
    return _plainPin != null && _plainPin!.isNotEmpty;
  }

  Widget _buildInfoRow(
    String label,
    String value,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: isDesktop
            ? 16.h
            : isTablet
            ? 14.h
            : isSmallScreen
            ? 10.h
            : 12.h,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isDesktop
                ? 120.w
                : isTablet
                ? 100.w
                : isSmallScreen
                ? 80.w
                : 90.w,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: isDesktop
                    ? 14.sp
                    : isTablet
                    ? 13.sp
                    : isSmallScreen
                    ? 11.sp
                    : 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.black87,
                fontSize: isDesktop
                    ? 14.sp
                    : isTablet
                    ? 13.sp
                    : isSmallScreen
                    ? 11.sp
                    : 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build specialized PIN row with toggle functionality
  Widget _buildPinRow(bool isTablet, bool isDesktop, bool isSmallScreen) {
    final canReveal = _canRevealPin();
    final displayValue = _isPinVisible && canReveal ? _plainPin! : '••••••';

    return Padding(
      padding: EdgeInsets.only(
        bottom: isDesktop
            ? 16.h
            : isTablet
            ? 14.h
            : isSmallScreen
            ? 10.h
            : 12.h,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isDesktop
                ? 120.w
                : isTablet
                ? 100.w
                : isSmallScreen
                ? 80.w
                : 90.w,
            child: Text(
              'PIN',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: isDesktop
                    ? 14.sp
                    : isTablet
                    ? 13.sp
                    : isSmallScreen
                    ? 11.sp
                    : 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayValue,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: isDesktop
                          ? 14.sp
                          : isTablet
                          ? 13.sp
                          : isSmallScreen
                          ? 11.sp
                          : 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (canReveal) ...[
                  SizedBox(width: 8.w),
                  GestureDetector(
                    onTap: _togglePinVisibility,
                    child: Container(
                      padding: EdgeInsets.all(4.w),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Icon(
                        _isPinVisible ? Icons.visibility_off : Icons.visibility,
                        size: isDesktop
                            ? 18.sp
                            : isTablet
                            ? 16.sp
                            : isSmallScreen
                            ? 14.sp
                            : 15.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(width: 8.w),
                  Tooltip(
                    message: 'Cannot reveal hashed PIN',
                    child: Container(
                      padding: EdgeInsets.all(4.w),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Icon(
                        Icons.visibility_off,
                        size: isDesktop
                            ? 18.sp
                            : isTablet
                            ? 16.sp
                            : isSmallScreen
                            ? 14.sp
                            : 15.sp,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalBalanceCard(
    Wallet wallet,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isDesktop
            ? 20.w
            : isTablet
            ? 16.w
            : 12.w,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ),
        borderRadius: BorderRadius.circular(isDesktop ? 16.r : 12.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.3),
            blurRadius: 8.r,
            spreadRadius: 1.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: isDesktop
                    ? 28.sp
                    : isTablet
                    ? 24.sp
                    : isSmallScreen
                    ? 20.sp
                    : 22.sp,
              ),
              SizedBox(width: 12.w),
              Text(
                'Total Balance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isDesktop
                      ? 18.sp
                      : isTablet
                      ? 16.sp
                      : isSmallScreen
                      ? 14.sp
                      : 15.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            '${wallet.totalBalance.toStringAsFixed(0)} SAR',
            style: TextStyle(
              color: Colors.white,
              fontSize: isDesktop
                  ? 32.sp
                  : isTablet
                  ? 28.sp
                  : isSmallScreen
                  ? 24.sp
                  : 26.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBalanceBreakdown(
                'Spending',
                wallet.spendingBalance,
                const Color(0xFFEF4444),
                isTablet,
                isDesktop,
                isSmallScreen,
              ),
              _buildBalanceBreakdown(
                'Savings',
                wallet.savingBalance,
                const Color(0xFF3B82F6),
                isTablet,
                isDesktop,
                isSmallScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceBreakdown(
    String label,
    double amount,
    Color color,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: isDesktop
                ? 12.sp
                : isTablet
                ? 11.sp
                : isSmallScreen
                ? 9.sp
                : 10.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          '${amount.toStringAsFixed(0)} SAR',
          style: TextStyle(
            color: Colors.white,
            fontSize: isDesktop
                ? 14.sp
                : isTablet
                ? 13.sp
                : isSmallScreen
                ? 11.sp
                : 12.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildWalletDetail(
    String title,
    double amount,
    IconData icon,
    Color color,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Container(
      padding: EdgeInsets.all(
        isDesktop
            ? 12.w
            : isTablet
            ? 10.w
            : 8.w,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isDesktop ? 8.r : 6.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: isDesktop
                ? 20.sp
                : isTablet
                ? 18.sp
                : isSmallScreen
                ? 14.sp
                : 16.sp,
          ),
          SizedBox(height: 4.h),
          Text(
            title,
            style: TextStyle(
              fontSize: isDesktop
                  ? 12.sp
                  : isTablet
                  ? 11.sp
                  : isSmallScreen
                  ? 9.sp
                  : 10.sp,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            '${amount.toStringAsFixed(0)} SAR',
            style: TextStyle(
              fontSize: isDesktop
                  ? 14.sp
                  : isTablet
                  ? 13.sp
                  : isSmallScreen
                  ? 11.sp
                  : 12.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingGoalProgress(
    Wallet wallet,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    final progress = wallet.savingGoal > 0
        ? wallet.savingBalance / wallet.savingGoal
        : 0.0;

    return Container(
      padding: EdgeInsets.all(
        isDesktop
            ? 12.w
            : isTablet
            ? 10.w
            : 8.w,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withOpacity(0.1),
        borderRadius: BorderRadius.circular(isDesktop ? 8.r : 6.r),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Saving Goal',
                style: TextStyle(
                  fontSize: isDesktop
                      ? 12.sp
                      : isTablet
                      ? 11.sp
                      : isSmallScreen
                      ? 9.sp
                      : 10.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: isDesktop
                      ? 12.sp
                      : isTablet
                      ? 11.sp
                      : isSmallScreen
                      ? 9.sp
                      : 10.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: const Color(0xFF3B82F6).withOpacity(0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            borderRadius: BorderRadius.circular(4.r),
          ),
          SizedBox(height: 4.h),
          Text(
            '${wallet.savingBalance.toStringAsFixed(0)} / ${wallet.savingGoal.toStringAsFixed(0)} SAR',
            style: TextStyle(
              fontSize: isDesktop
                  ? 11.sp
                  : isTablet
                  ? 10.sp
                  : isSmallScreen
                  ? 8.sp
                  : 9.sp,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // Savings Transactions Expandable Section
  Widget _buildSavingsTransactionsSection(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 16.r : 12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Icon(
              Icons.savings,
              color: const Color(0xFF10B981),
              size: isDesktop
                  ? 24.sp
                  : isTablet
                  ? 22.sp
                  : isSmallScreen
                  ? 18.sp
                  : 20.sp,
            ),
            SizedBox(width: 12.w),
            Text(
              'Savings Transactions',
              style: TextStyle(
                fontSize: isDesktop
                    ? 18.sp
                    : isTablet
                    ? 16.sp
                    : isSmallScreen
                    ? 14.sp
                    : 15.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop
                  ? 16.w
                  : isTablet
                  ? 14.w
                  : 12.w,
              vertical: 8.h,
            ),
            child: StreamBuilder<List<app_transaction.Transaction>>(
              stream: FirebaseService.getChildWalletTransactionsStream(
                widget.parentId,
                widget.child.id,
                'saving',
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(40.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: const Color(0xFFFF8A00),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(40.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64.sp,
                          color: const Color(0xFFFF6A5D),
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          'Error loading transactions',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFFF6A5D),
                            fontFamily: 'SF Pro Text',
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final transactions = snapshot.data ?? [];

                if (transactions.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(40.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64.sp,
                          color: const Color(0xFFA29EB6),
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          'No savings transactions yet',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFA29EB6),
                            fontFamily: 'SF Pro Text',
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: transactions
                      .map(
                        (transaction) =>
                            _buildWalletTransactionItem(transaction),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Spending Transactions Expandable Section
  Widget _buildSpendingTransactionsSection(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 16.r : 12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Row(
          children: [
            Icon(
              Icons.shopping_cart,
              color: const Color(0xFFEF4444),
              size: isDesktop
                  ? 24.sp
                  : isTablet
                  ? 22.sp
                  : isSmallScreen
                  ? 18.sp
                  : 20.sp,
            ),
            SizedBox(width: 12.w),
            Text(
              'Spending Transactions',
              style: TextStyle(
                fontSize: isDesktop
                    ? 18.sp
                    : isTablet
                    ? 16.sp
                    : isSmallScreen
                    ? 14.sp
                    : 15.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop
                  ? 16.w
                  : isTablet
                  ? 14.w
                  : 12.w,
              vertical: 8.h,
            ),
            child: StreamBuilder<List<app_transaction.Transaction>>(
              stream: FirebaseService.getChildWalletTransactionsStream(
                widget.parentId,
                widget.child.id,
                'spending',
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(40.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: const Color(0xFFFF8A00),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(40.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64.sp,
                          color: const Color(0xFFFF6A5D),
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          'Error loading transactions',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFFF6A5D),
                            fontFamily: 'SF Pro Text',
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final transactions = snapshot.data ?? [];

                if (transactions.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(40.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64.sp,
                          color: const Color(0xFFA29EB6),
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          'No spending transactions yet',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFA29EB6),
                            fontFamily: 'SF Pro Text',
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: transactions
                      .map(
                        (transaction) =>
                            _buildWalletTransactionItem(transaction),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletStatistics(
    Wallet wallet,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Container(
      padding: EdgeInsets.all(
        isDesktop
            ? 20.w
            : isTablet
            ? 16.w
            : 12.w,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 16.r : 12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10.r,
            spreadRadius: 1.r,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wallet Statistics',
            style: TextStyle(
              fontSize: isDesktop
                  ? 18.sp
                  : isTablet
                  ? 16.sp
                  : isSmallScreen
                  ? 14.sp
                  : 15.sp,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 16.h),

          // Wallet Details Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total Balance',
                  '${wallet.totalBalance.toStringAsFixed(0)} SAR',
                  Icons.account_balance_wallet,
                  const Color(0xFF10B981),
                  isTablet,
                  isDesktop,
                  isSmallScreen,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildStatCard(
                  'Spending Money',
                  '${wallet.spendingBalance.toStringAsFixed(0)} SAR',
                  Icons.shopping_cart,
                  const Color(0xFFEF4444),
                  isTablet,
                  isDesktop,
                  isSmallScreen,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Savings',
                  '${wallet.savingBalance.toStringAsFixed(0)} SAR',
                  Icons.savings,
                  const Color(0xFF3B82F6),
                  isTablet,
                  isDesktop,
                  isSmallScreen,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildStatCard(
                  'Saving Goal',
                  '${wallet.savingGoal.toStringAsFixed(0)} SAR',
                  Icons.flag,
                  const Color(0xFF8B5CF6),
                  isTablet,
                  isDesktop,
                  isSmallScreen,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),

          // Progress Information
          Container(
            padding: EdgeInsets.all(
              isDesktop
                  ? 16.w
                  : isTablet
                  ? 14.w
                  : 12.w,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.05),
              borderRadius: BorderRadius.circular(isDesktop ? 12.r : 8.r),
              border: Border.all(
                color: const Color(0xFF3B82F6).withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Goal Progress',
                      style: TextStyle(
                        fontSize: isDesktop
                            ? 14.sp
                            : isTablet
                            ? 13.sp
                            : isSmallScreen
                            ? 11.sp
                            : 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${wallet.savingGoal > 0 ? ((wallet.savingBalance / wallet.savingGoal) * 100).toStringAsFixed(0) : '0'}%',
                      style: TextStyle(
                        fontSize: isDesktop
                            ? 14.sp
                            : isTablet
                            ? 13.sp
                            : isSmallScreen
                            ? 11.sp
                            : 12.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                LinearProgressIndicator(
                  value: wallet.savingGoal > 0
                      ? (wallet.savingBalance / wallet.savingGoal).clamp(
                          0.0,
                          1.0,
                        )
                      : 0.0,
                  backgroundColor: const Color(0xFF3B82F6).withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF3B82F6),
                  ),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                SizedBox(height: 8.h),
                Text(
                  '${wallet.savingBalance.toStringAsFixed(0)} SAR saved out of ${wallet.savingGoal.toStringAsFixed(0)} SAR goal',
                  style: TextStyle(
                    fontSize: isDesktop
                        ? 12.sp
                        : isTablet
                        ? 11.sp
                        : isSmallScreen
                        ? 9.sp
                        : 10.sp,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    return Container(
      padding: EdgeInsets.all(
        isDesktop
            ? 16.w
            : isTablet
            ? 14.w
            : 12.w,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isDesktop ? 12.r : 8.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: isDesktop
                ? 24.sp
                : isTablet
                ? 22.sp
                : isSmallScreen
                ? 18.sp
                : 20.sp,
          ),
          SizedBox(height: 8.h),
          Text(
            title,
            style: TextStyle(
              fontSize: isDesktop
                  ? 12.sp
                  : isTablet
                  ? 11.sp
                  : isSmallScreen
                  ? 9.sp
                  : 10.sp,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: isDesktop
                  ? 14.sp
                  : isTablet
                  ? 13.sp
                  : isSmallScreen
                  ? 11.sp
                  : 12.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(
    app_transaction.Transaction transaction,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
  ) {
    final isIncome =
        transaction.type == 'transfer' && transaction.toWallet == 'total';

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(
        isDesktop
            ? 12.w
            : isTablet
            ? 10.w
            : 8.w,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(isDesktop ? 8.r : 6.r),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(
              isDesktop
                  ? 8.w
                  : isTablet
                  ? 6.w
                  : 4.w,
            ),
            decoration: BoxDecoration(
              color:
                  (isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                      .withOpacity(0.1),
              borderRadius: BorderRadius.circular(isDesktop ? 6.r : 4.r),
            ),
            child: Icon(
              isIncome ? Icons.arrow_upward : Icons.arrow_downward,
              color: isIncome
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              size: isDesktop
                  ? 16.sp
                  : isTablet
                  ? 14.sp
                  : isSmallScreen
                  ? 12.sp
                  : 13.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: TextStyle(
                    fontSize: isDesktop
                        ? 13.sp
                        : isTablet
                        ? 12.sp
                        : isSmallScreen
                        ? 10.sp
                        : 11.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  transaction.category,
                  style: TextStyle(
                    fontSize: isDesktop
                        ? 11.sp
                        : isTablet
                        ? 10.sp
                        : isSmallScreen
                        ? 8.sp
                        : 9.sp,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'}${transaction.amount.toStringAsFixed(0)} SAR',
            style: TextStyle(
              fontSize: isDesktop
                  ? 13.sp
                  : isTablet
                  ? 12.sp
                  : isSmallScreen
                  ? 10.sp
                  : 11.sp,
              fontWeight: FontWeight.bold,
              color: isIncome
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  // Transaction Item Widget (copied from SpendingWalletScreen)
  Widget _buildWalletTransactionItem(app_transaction.Transaction transaction) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Row(
        children: [
          // Category Icon
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: _getCategoryColor(
                transaction.category,
              ).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              _getCategoryIcon(transaction.category),
              color: _getCategoryColor(transaction.category),
              size: 20.sp,
            ),
          ),
          SizedBox(width: 12.w),

          // Transaction Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1243),
                    fontFamily: 'SF Pro Text',
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _getCategoryName(transaction.category),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFFA29EB6),
                    fontFamily: 'SF Pro Text',
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _formatDate(transaction.date),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFFA29EB6),
                    fontFamily: 'SF Pro Text',
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Text(
            _getTransactionAmountText(transaction),
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: _getTransactionAmountColor(transaction),
              fontFamily: 'SF Pro Text',
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods (copied from SpendingWalletScreen)
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'food':
        return const Color(0xFFFF8A00);
      case 'gaming':
        return const Color(0xFF643FDB);
      case 'movies':
        return const Color(0xFF47C272);
      default:
        return const Color(0xFFA29EB6);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'food':
        return Icons.restaurant;
      case 'gaming':
        return Icons.sports_esports;
      case 'movies':
        return Icons.movie;
      default:
        return Icons.shopping_bag;
    }
  }

  String _getCategoryName(String category) {
    switch (category) {
      case 'food':
        return 'Food & Dining';
      case 'gaming':
        return 'Gaming';
      case 'movies':
        return 'Entertainment';
      default:
        return 'Other';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getTransactionAmountText(app_transaction.Transaction transaction) {
    // Check if this is a transfer FROM spending TO saving (negative/red)
    if (transaction.fromWallet == 'spending' &&
        transaction.toWallet == 'saving') {
      return '-${transaction.amount.toStringAsFixed(2)} SAR';
    }

    // Check if this is a transfer FROM saving TO spending (positive/green)
    if (transaction.fromWallet == 'saving' &&
        transaction.toWallet == 'spending') {
      return '+${transaction.amount.toStringAsFixed(2)} SAR';
    }

    // Check if this is a wallet-to-wallet transaction from total (positive/green)
    if (transaction.fromWallet == 'total' &&
        transaction.toWallet == 'spending') {
      return '+${transaction.amount.toStringAsFixed(2)} SAR';
    }

    // Check if this is wishlist spending (negative/red)
    if (transaction.category == 'wishlist') {
      return '-${transaction.amount.toStringAsFixed(2)} SAR';
    }

    // Only show wallet-to-wallet transactions, no external spending
    return '+${transaction.amount.toStringAsFixed(2)} SAR';
  }

  Color _getTransactionAmountColor(app_transaction.Transaction transaction) {
    // Check if this is a transfer FROM spending TO saving (negative/red)
    if (transaction.fromWallet == 'spending' &&
        transaction.toWallet == 'saving') {
      return const Color(0xFFFF6A5D); // Red
    }

    // Check if this is a transfer FROM saving TO spending (positive/green)
    if (transaction.fromWallet == 'saving' &&
        transaction.toWallet == 'spending') {
      return const Color(0xFF47C272); // Green
    }

    // Check if this is a wallet-to-wallet transaction from total (positive/green)
    if (transaction.fromWallet == 'total' &&
        transaction.toWallet == 'spending') {
      return const Color(0xFF47C272); // Green
    }

    // Check if this is wishlist spending (negative/red)
    if (transaction.category == 'wishlist') {
      return const Color(0xFFFF6A5D); // Red
    }

    // Only show wallet-to-wallet transactions as positive/green
    return const Color(0xFF47C272); // Green
  }
}
