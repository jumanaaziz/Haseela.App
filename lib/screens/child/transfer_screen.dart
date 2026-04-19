import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import '../../models/wallet.dart';
import '../../models/transaction.dart';
import '../services/firebase_service.dart';

class TransferScreen extends StatefulWidget {
  final Wallet userWallet;
  final String parentId;
  final String childId;
  final Function(Wallet) onWalletUpdated;
  final double? savingGoal;
  final bool? isSavingGoalReached;

  const TransferScreen({
    super.key,
    required this.userWallet,
    required this.parentId,
    required this.childId,
    required this.onWalletUpdated,
    this.savingGoal,
    this.isSavingGoalReached,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final TextEditingController _amountController = TextEditingController();
  String _fromWallet = 'total';
  String _toWallet = 'spending';
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F3),
      appBar: AppBar(
        title: Text(
          'Transfer Money',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            fontFamily: 'SF Pro Text',
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1C1243),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Balances
            _buildBalanceCard(),
            SizedBox(height: 24.h),

            // Transfer Form
            _buildTransferForm(),
            SizedBox(height: 32.h),

            // Transfer Button
            _buildTransferButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Balances',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1C1243),
              fontFamily: 'SF Pro Text',
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: _buildBalanceItem(
                  'Total',
                  widget.userWallet.totalBalance,
                  const Color(0xFF643FDB),
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: _buildBalanceItem(
                  'Spending',
                  widget.userWallet.spendingBalance,
                  const Color(0xFFFF8A00),
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: _buildBalanceItem(
                  'Saving',
                  widget.userWallet.savingBalance,
                  const Color(0xFF47C272),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceItem(String label, double amount, Color color) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFA29EB6),
              fontFamily: 'SF Pro Text',
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            '${amount.toStringAsFixed(2)} SAR',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'SF Pro Text',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferForm() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transfer Details',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1C1243),
              fontFamily: 'SF Pro Text',
            ),
          ),
          SizedBox(height: 20.h),

          // Amount Input
          Text(
            'Amount (SAR)',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1C1243),
              fontFamily: 'SF Pro Text',
            ),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              // Only allow digits, one decimal point, and limit to 2 decimal places
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              TextInputFormatter.withFunction((oldValue, newValue) {
                // Prevent empty input
                if (newValue.text.isEmpty) return newValue;

                // Prevent multiple decimal points
                if (newValue.text.split('.').length > 2) {
                  return oldValue;
                }

                // Prevent leading zeros (except for 0.xx format)
                if (newValue.text.length > 1 &&
                    newValue.text.startsWith('0') &&
                    !newValue.text.startsWith('0.')) {
                  return oldValue;
                }

                // Parse and validate the value
                final value = double.tryParse(newValue.text);
                if (value == null || value <= 0) {
                  return oldValue;
                }

                // Prevent very large numbers (limit to 999999.99)
                if (value > 999999.99) {
                  return oldValue;
                }

                return newValue;
              }),
            ],
            decoration: InputDecoration(
              hintText: 'Enter amount (e.g., 50.00)',
              labelText: 'Transfer Amount (SAR)',
              helperText: 'Enter a positive amount between 0.01 and 999,999.99',
              helperStyle: TextStyle(
                fontSize: 12.sp,
                color: const Color(0xFF718096),
                fontFamily: 'SF Pro Text',
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide(color: const Color(0xFFA29EB6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide(color: const Color(0xFF643FDB)),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide(color: const Color(0xFFFF6A5D)),
              ),
              prefixIcon: Icon(
                Icons.attach_money,
                color: const Color(0xFF643FDB),
                size: 20.sp,
              ),
            ),
            onChanged: (value) {
              // Real-time validation feedback
              if (value.isNotEmpty) {
                final parsedValue = double.tryParse(value);
                if (parsedValue != null && parsedValue > 0) {
                  // Valid input - no error
                } else {
                  // Invalid input - will be handled by input formatters
                }
              }
            },
          ),
          SizedBox(height: 20.h),

          // From Wallet
          Text(
            'From',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1C1243),
              fontFamily: 'SF Pro Text',
            ),
          ),
          SizedBox(height: 8.h),
          DropdownButtonFormField<String>(
            value: _fromWallet,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide(color: const Color(0xFFA29EB6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide(color: const Color(0xFF643FDB)),
              ),
            ),
            items: [
              DropdownMenuItem(value: 'total', child: Text('Total Wallet')),
              DropdownMenuItem(
                value: 'spending',
                child: Text('Spending Wallet'),
              ),
              DropdownMenuItem(value: 'saving', child: Text('Saving Wallet')),
            ],
            onChanged: (value) {
              setState(() {
                _fromWallet = value!;
                // Reset to wallet if same as from
                if (_toWallet == _fromWallet) {
                  _toWallet = _fromWallet == 'total' ? 'spending' : 'total';
                }
              });
            },
          ),
          SizedBox(height: 20.h),

          // To Wallet
          Text(
            'To',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1C1243),
              fontFamily: 'SF Pro Text',
            ),
          ),
          SizedBox(height: 8.h),
          DropdownButtonFormField<String>(
            value: _toWallet,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide(color: const Color(0xFFA29EB6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide(color: const Color(0xFF643FDB)),
              ),
            ),
            items: [
              DropdownMenuItem(value: 'total', child: Text('Total Wallet')),
              DropdownMenuItem(
                value: 'spending',
                child: Text('Spending Wallet'),
              ),
              DropdownMenuItem(value: 'saving', child: Text('Saving Wallet')),
            ],
            onChanged: (value) {
              setState(() {
                _toWallet = value!;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransferButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _performTransfer,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF643FDB),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
          ),
        ),
        child: _isLoading
            ? SizedBox(
                height: 20.h,
                width: 20.w,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Transfer',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SF Pro Text',
                ),
              ),
      ),
    );
  }

  Future<void> _performTransfer() async {
    // Enhanced validation
final amount = double.tryParse(_amountController.text);

double fromBalance = 0;
switch (_fromWallet) {
  case 'total':
    fromBalance = widget.userWallet.totalBalance;
    break;
  case 'spending':
    fromBalance = widget.userWallet.spendingBalance;
    break;
  case 'saving':
    fromBalance = widget.userWallet.savingBalance;
    break;
}

bool isInvalidTransfer =
    _amountController.text.isEmpty ||
    amount == null ||
    amount <= 0 ||
    amount > 999999.99 ||
    _fromWallet == _toWallet ||
    (_fromWallet == 'saving' && !(widget.isSavingGoalReached ?? true)) ||
    amount > fromBalance;

if (isInvalidTransfer) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Invalid transfer request. Please check your input.'),
      backgroundColor: const Color(0xFFFF6A5D),
    ),
  );
  return;
}

    setState(() {
      _isLoading = true;
    });

    try {
      // Calculate new balances
      double newTotalBalance = widget.userWallet.totalBalance;
      double newSpendingBalance = widget.userWallet.spendingBalance;
      double newSavingBalance = widget.userWallet.savingBalance;

      // Deduct from source
      switch (_fromWallet) {
        case 'total':
          newTotalBalance -= amount;
          break;
        case 'spending':
          newSpendingBalance -= amount;
          break;
        case 'saving':
          newSavingBalance -= amount;
          break;
      }

      // Add to destination
      switch (_toWallet) {
        case 'total':
          newTotalBalance += amount;
          break;
        case 'spending':
          newSpendingBalance += amount;
          break;
        case 'saving':
          newSavingBalance += amount;
          break;
      }

      // Update wallet in Firebase
      final success = await FirebaseService.updateChildWalletBalance(
        widget.parentId,
        widget.childId,
        totalBalance: newTotalBalance,
        spendingBalance: newSpendingBalance,
        savingBalance: newSavingBalance,
      );

      if (success) {
        // Create transaction record
        final transaction = Transaction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          userId: widget.childId,
          walletId: widget.userWallet.id,
          type: 'transfer',
          category: 'transfer',
          amount: amount,
          description:
              'Transfer from ${_getWalletName(_fromWallet)} to ${_getWalletName(_toWallet)}',
          date: DateTime.now(),
          fromWallet: _fromWallet,
          toWallet: _toWallet,
        );

        await FirebaseService.createChildTransaction(
          widget.parentId,
          widget.childId,
          transaction,
        );

        // Update local wallet
        final updatedWallet = widget.userWallet.copyWith(
          totalBalance: newTotalBalance,
          spendingBalance: newSpendingBalance,
          savingBalance: newSavingBalance,
        );

        widget.onWalletUpdated(updatedWallet);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transfer completed successfully!'),
              backgroundColor: const Color(0xFF47C272),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transfer failed. Please try again.'),
              backgroundColor: const Color(0xFFFF6A5D),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFFF6A5D),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getWalletName(String walletType) {
    switch (walletType) {
      case 'total':
        return 'Total Wallet';
      case 'spending':
        return 'Spending Wallet';
      case 'saving':
        return 'Saving Wallet';
      default:
        return walletType;
    }
  }
}
