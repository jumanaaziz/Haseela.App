import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// LESSON 2: Earning Your Allowance — Redesigned Educational Version
///
/// LEARNING GOAL: By the end of this lesson, children will understand that money is earned
/// by doing work, helping others, or using skills to provide value, and will be able to
/// identify activities that help them earn money versus activities that cost money.
///
/// EDUCATIONAL VALUE:
/// - Teaches the fundamental concept: money comes from work and value creation
/// - Distinguishes earning activities (work, helping, skills) from spending activities
/// - Uses concrete, age-appropriate examples children can relate to (chores, helping neighbors, using talents)
/// - Builds on Lesson 1 by showing WHERE money comes from (not just what it can buy)
/// - Prepares children for understanding allowances, chores, and future earning opportunities
///
/// RESEARCH BASIS & LEARNING SCIENCE PRINCIPLES:
/// - Scaffolding (Vygotsky): Starts with simple, obvious examples (doing chores), progresses to
///   more nuanced concepts (using skills, helping others). Builds complexity gradually.
/// - Active Learning (Piaget): Children actively choose and reason about each scenario, not
///   passive reading. Requires decision-making and critical thinking.
/// - Immediate Feedback (Hattie & Timperley, 2007): Each choice provides specific explanation
///   of why it's correct/incorrect, improving retention and understanding.
/// - Chunking (Miller, 1956): Information broken into small, manageable scenarios (3-4 choices
///   per question) appropriate for working memory capacity of 9-12 year olds.
/// - Concrete Examples (Bruner): Uses real activities children know (walking dogs, helping
///   neighbors, doing homework) rather than abstract concepts.
/// - Age-Appropriate Difficulty: Based on cognitive development stages (Piaget's Concrete
///   Operational Stage, ages 7-12), children can reason about cause-and-effect relationships
///   and understand that work leads to earning.
/// - Intrinsic Motivation (Deci & Ryan): Provides autonomy (they choose), competence (clear
///   progress), and relatedness (Haseel character story).

class Lesson2MiniChallengeScreen extends StatefulWidget {
  final String childName;
  final int currentLesson;
  final int totalLessons;
  final String childId;
  final VoidCallback onComplete;

  const Lesson2MiniChallengeScreen({
    super.key,
    required this.childName,
    required this.currentLesson,
    required this.totalLessons,
    required this.childId,
    required this.onComplete,
  });

  @override
  State<Lesson2MiniChallengeScreen> createState() =>
      _Lesson2MiniChallengeScreenState();
}

class EarningScenario {
  final String scenario;
  final List<String> options;
  final List<String> optionEmojis;
  final int correctIndex;
  final String explanation;

  EarningScenario({
    required this.scenario,
    required this.options,
    required this.optionEmojis,
    required this.correctIndex,
    required this.explanation,
  });
}

class _Lesson2MiniChallengeScreenState extends State<Lesson2MiniChallengeScreen>
    with TickerProviderStateMixin {
  late AnimationController _haseelController;
  late AnimationController _celebrationController;
  late AnimationController _pulseController;
  late AnimationController _feedbackController;

  List<EarningScenario> _scenarios = [];
  int _currentScenarioIndex = 0;
  int _selectedOptionIndex = -1;
  int _correctAnswers = 0;
  bool _showFeedback = false;
  bool _isCompleted = false;
  bool _showCelebration = false;

  @override
  void initState() {
    super.initState();
    _initializeScenarios();
    _initializeAnimations();
  }

  void _initializeScenarios() {
    _scenarios = [
      // Scenario 1: Simple, obvious - doing chores
      EarningScenario(
        scenario:
            'Haseel wants to earn 10 Riyals. Which activity would help Haseel EARN money?',
        options: [
          'Doing chores at home',
          'Buying a toy',
          'Playing video games',
          'Asking for money without doing anything',
        ],
        optionEmojis: ['🧹', '🛍️', '🎮', '🤷'],
        correctIndex: 0,
        explanation:
            'Great! Doing chores is work, and work helps you earn money. When you help at home, you\'re providing value, which is how earning works!',
      ),
      // Scenario 2: Helping others
      EarningScenario(
        scenario:
            'Haseel\'s neighbor needs help. Which would help Haseel EARN money?',
        options: [
          'Helping neighbor walk their dog',
          'Borrowing money from neighbor',
          'Ignoring the neighbor',
          'Asking neighbor to give money for free',
        ],
        optionEmojis: ['🐕', '💰', '😴', '🤲'],
        correctIndex: 0,
        explanation:
            'Perfect! Helping others with work (like walking a dog) is a way to earn money. You\'re doing something useful, and that creates value!',
      ),
      // Scenario 3: Using skills
      EarningScenario(
        scenario:
            'Haseel is good at drawing. How could Haseel use this skill to EARN money?',
        options: [
          'Drawing pictures for friends (for a small fee)',
          'Buying expensive art supplies',
          'Only drawing for free',
          'Not using the skill at all',
        ],
        optionEmojis: ['🎨', '🛒', '🆓', '❌'],
        correctIndex: 0,
        explanation:
            'Excellent thinking! Using your skills (like drawing) to help others is a great way to earn money. Your talents have value!',
      ),
      // Scenario 4: More nuanced - earning vs spending
      EarningScenario(
        scenario:
            'Haseel wants to save up for a new book. Which activity helps EARN money to reach this goal?',
        options: [
          'Helping at a family shop',
          'Spending all allowance immediately',
          'Waiting for someone to give money',
          'Buying the book with borrowed money',
        ],
        optionEmojis: ['🏪', '💸', '⏳', '📚'],
        correctIndex: 0,
        explanation:
            'Smart choice! Helping at a shop is work, and work earns money. To save for goals, you need to earn money first!',
      ),
    ];
  }

  void _initializeAnimations() {
    _haseelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _haseelController.dispose();
    _celebrationController.dispose();
    _pulseController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  void _selectOption(int index) {
    if (_showFeedback) return;

    setState(() {
      _selectedOptionIndex = index;
      _showFeedback = true;
    });

    _feedbackController.forward().then((_) {
      _feedbackController.reverse();
    });

    final scenario = _scenarios[_currentScenarioIndex];
    final isCorrect = index == scenario.correctIndex;

    if (isCorrect) {
      setState(() {
        _correctAnswers++;
      });
    }

    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isCorrect ? Icons.check_circle : Icons.info_outline,
              color: Colors.white,
              size: 24.sp,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                isCorrect
                    ? scenario.explanation
                    : 'Think again! Remember: Earning means you DO work or help others. Which option involves doing something?',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: isCorrect
            ? const Color(0xFF10B981)
            : const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        margin: EdgeInsets.all(16.w),
        duration: Duration(seconds: isCorrect ? 4 : 3),
      ),
    );

    // Move to next scenario after delay
    Future.delayed(Duration(seconds: isCorrect ? 4 : 3), () {
      _nextScenario();
    });
  }

  void _nextScenario() {
    if (_currentScenarioIndex < _scenarios.length - 1) {
      setState(() {
        _currentScenarioIndex++;
        _selectedOptionIndex = -1;
        _showFeedback = false;
      });
    } else {
      _completeLesson();
    }
  }

  void _completeLesson() {
    setState(() {
      _isCompleted = true;
      _showCelebration = true;
    });
    _celebrationController.forward();

    Future.delayed(const Duration(seconds: 4), () {
      widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth > 600;
          final isSmallScreen = constraints.maxWidth < 400;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFDBEAFE), // Light blue
                  Color(0xFFFEF3C7), // Light yellow
                  Color(0xFFE0F2FE), // Light teal
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  // Floating coins
                  _buildFloatingCoins(),

                  // Main content
                  SingleChildScrollView(
                    padding: EdgeInsets.all(isSmallScreen ? 16.w : 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProgressTracker(),
                        SizedBox(height: isTablet ? 32.h : 24.h),
                        _buildTitle(),
                        SizedBox(height: isTablet ? 32.h : 24.h),
                        _buildHaseelSection(),
                        SizedBox(height: isTablet ? 40.h : 32.h),
                        if (!_isCompleted) ...[
                          _buildScenarioCard(),
                          SizedBox(height: isTablet ? 32.h : 24.h),
                          _buildOptionsGrid(),
                          SizedBox(height: isTablet ? 32.h : 24.h),
                          _buildProgressIndicator(),
                        ],
                      ],
                    ),
                  ),

                  // Celebration overlay
                  if (_showCelebration) _buildCelebrationOverlay(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressTracker() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                padding: EdgeInsets.all(8.w),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: const Color(0xFF475569),
                  size: 28.sp,
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Mini Challenge ${widget.currentLesson}/${widget.totalLessons}',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 4.h,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        '${((widget.currentLesson / widget.totalLessons) * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                Container(
                  height: 10.h,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.currentLesson / widget.totalLessons,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                        ),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.work, color: Colors.white, size: 32.sp),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  'Mini Challenge: How to Earn Money',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            'Help Haseel learn how to earn Riyals!',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHaseelSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _haseelController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  0,
                  5 * (0.5 - (0.5 - _haseelController.value).abs()),
                ),
                child: Container(
                  padding: EdgeInsets.all(20.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFE0F2FE),
                        const Color(0xFFDBEAFE).withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withOpacity(0.4),
                      width: 2.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('🐇', style: TextStyle(fontSize: 32.sp)),
                          SizedBox(width: 8.w),
                          Text(
                            'Haseel says:',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF3B82F6),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16.h),
                      Container(
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          _isCompleted
                              ? '"Wow! I learned so much about earning money! Thank you for helping me understand that money comes from doing work, helping others, and using my skills!"'
                              : '"I want to earn some Riyals, but I\'m not sure how! Can you help me figure out which activities help me EARN money? Remember: earning means doing work or helping others!"',
                          style: TextStyle(
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioCard() {
    final scenario = _scenarios[_currentScenarioIndex];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  'Question ${_currentScenarioIndex + 1}/${_scenarios.length}',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Text(
            scenario.scenario,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsGrid() {
    final scenario = _scenarios[_currentScenarioIndex];

    return Column(
      children: scenario.options.asMap().entries.map((entry) {
        final index = entry.key;
        final option = entry.value;
        final emoji = scenario.optionEmojis[index];
        final isSelected = _selectedOptionIndex == index;
        final isCorrect = index == scenario.correctIndex;

        return Container(
          margin: EdgeInsets.only(bottom: 12.h),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectOption(index),
              borderRadius: BorderRadius.circular(16.r),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: EdgeInsets.all(18.w),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isCorrect
                            ? const Color(0xFF10B981).withOpacity(0.1)
                            : const Color(0xFFEF4444).withOpacity(0.1))
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: isSelected
                        ? (isCorrect
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444))
                        : const Color(0xFFE2E8F0),
                    width: isSelected ? 3 : 2,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                (isCorrect
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFEF4444))
                                    .withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56.w,
                      height: 56.w,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isCorrect
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444))
                            : const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: Center(
                        child: Text(emoji, style: TextStyle(fontSize: 28.sp)),
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        isCorrect ? Icons.check_circle : Icons.cancel,
                        color: isCorrect
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        size: 28.sp,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Correct Answers',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                '$_correctAnswers/${_scenarios.length}',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Progress',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                '${_currentScenarioIndex + 1}/${_scenarios.length}',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingCoins() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Positioned(
                  top:
                      MediaQuery.of(context).size.height * 0.1 +
                      (30 * _pulseController.value),
                  left:
                      MediaQuery.of(context).size.width * 0.1 +
                      (20 * _pulseController.value),
                  child: Opacity(
                    opacity: 0.6,
                    child: Container(
                      width: 30.w,
                      height: 30.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.monetization_on,
                        color: Colors.white,
                        size: 20.sp,
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Positioned(
                  top:
                      MediaQuery.of(context).size.height * 0.3 +
                      (25 * (1 - _pulseController.value)),
                  right:
                      MediaQuery.of(context).size.width * 0.15 +
                      (15 * (1 - _pulseController.value)),
                  child: Opacity(
                    opacity: 0.5,
                    child: Container(
                      width: 25.w,
                      height: 25.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAB308),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEAB308).withOpacity(0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.monetization_on,
                        color: Colors.white,
                        size: 16.sp,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCelebrationOverlay() {
    return AnimatedBuilder(
      animation: _celebrationController,
      builder: (context, child) {
        return Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.5 * _celebrationController.value),
            child: Center(
              child: Transform.scale(
                scale: 0.8 + (0.2 * _celebrationController.value),
                child: Opacity(
                  opacity: _celebrationController.value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 220.w,
                        height: 220.w,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF3B82F6,
                              ).withOpacity(0.6 * _celebrationController.value),
                              blurRadius: 40,
                              offset: const Offset(0, 15),
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ...List.generate(3, (index) {
                              return Container(
                                width: 220.w + (index * 30.w),
                                height: 220.w + (index * 30.w),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(
                                      0xFF3B82F6,
                                    ).withOpacity(0.3 * (1 - (index * 0.3))),
                                    width: 3,
                                  ),
                                ),
                              );
                            }),
                            Icon(
                              Icons.celebration_rounded,
                              color: Colors.white,
                              size: 110.sp,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 32.h),
                      Text(
                        '🎉 Excellent Work! 🎉',
                        style: TextStyle(
                          fontSize: 32.sp,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24.w,
                          vertical: 12.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'You got $_correctAnswers out of ${_scenarios.length} correct!',
                              style: TextStyle(
                                fontSize: 20.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 12.h),
                            Container(
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Text(
                                '💡 Key Idea: Earning = You work, help others, or use skills to GET money. Spending = You USE money to buy things. Understanding this helps you make smart choices!',
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 24.sp,
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'Moving to next lesson...',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
