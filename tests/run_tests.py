#!/usr/bin/env python3
"""
Master test runner for CPC comprehensive testing
"""

import sys
import os
import subprocess
import time
from pathlib import Path


class CPCTestRunner:
    """Comprehensive test runner for CPC"""
    
    def __init__(self):
        self.project_root = Path(__file__).parent.parent
        self.test_results = {}
        
    def run_test_suite(self, suite_name, test_files, markers=None):
        """Run a test suite with specified files"""
        print(f"\n{'='*60}")
        print(f"Running {suite_name}")
        print(f"{'='*60}")
        
        for test_file in test_files:
            test_path = self.project_root / test_file
            if not test_path.exists():
                print(f"⚠️  Test file not found: {test_file}")
                continue
                
            print(f"\n🧪 Running: {test_file}")
            
            cmd = ['python', '-m', 'pytest', str(test_path), '-v']
            if markers:
                cmd.extend(['-m', markers])
            
            start_time = time.time()
            try:
                result = subprocess.run(
                    cmd,
                    cwd=self.project_root,
                    capture_output=True,
                    text=True,
                    timeout=300  # 5 minute timeout per test file
                )
                
                duration = time.time() - start_time
                
                if result.returncode == 0:
                    print(f"✅ PASSED ({duration:.2f}s)")
                    self.test_results[test_file] = {'status': 'PASSED', 'duration': duration}
                else:
                    print(f"❌ FAILED ({duration:.2f}s)")
                    print(f"Error output: {result.stderr}")
                    self.test_results[test_file] = {'status': 'FAILED', 'duration': duration, 'error': result.stderr}
                    
            except subprocess.TimeoutExpired:
                print(f"⏰ TIMEOUT (>300s)")
                self.test_results[test_file] = {'status': 'TIMEOUT', 'duration': 300}
            except Exception as e:
                print(f"💥 ERROR: {e}")
                self.test_results[test_file] = {'status': 'ERROR', 'error': str(e)}
    
    def run_all_tests(self):
        """Run all test suites"""
        print("🚀 Starting CPC Comprehensive Test Suite")
        print(f"Project root: {self.project_root}")
        
        # Fast unit tests
        self.run_test_suite(
            "Core Unit Tests",
            [
                'tests/unit/test_cpc_comprehensive.py',
                'tests/unit/test_cpc_modules.py'
            ]
        )
        
        # Performance tests
        self.run_test_suite(
            "Performance Tests", 
            ['tests/unit/test_cpc_performance.py']
        )
        
        # Integration tests (fast)
        self.run_test_suite(
            "Integration Tests (Fast)",
            ['tests/integration/test_cpc_workflows.py'],
            markers='integration and not slow'
        )
        
        # Slow tests (optional)
        print(f"\n{'='*60}")
        print("Slow Integration Tests (optional)")
        print(f"{'='*60}")
        print("⏳ Running slow tests (may take several minutes)...")
        
        self.run_test_suite(
            "Integration Tests (Slow)",
            ['tests/integration/test_cpc_workflows.py'],
            markers='slow'
        )
    
    def quick_tests(self):
        """Run quick tests (unit tests only)"""
        test_files = [
            'tests/unit/test_cpc_comprehensive.py',
            'tests/unit/test_cpc_modules.py'
        ]
        self.run_test_suite("Quick Tests", test_files)
    
    def functional_tests(self):
        """Run functional tests (actual functionality testing)"""
        test_files = [
            'tests/unit/test_cpc_functional.py'
        ]
        self.run_test_suite("Functional Tests", test_files)
    
    def run_performance_tests(self):
        """Run only performance tests"""
        print("🏃 Running Performance Test Suite")
        
        self.run_test_suite(
            "Performance Tests",
            ['tests/unit/test_cpc_performance.py']
        )
    
    def print_summary(self):
        """Print test summary"""
        print(f"\n{'='*60}")
        print("TEST SUMMARY")
        print(f"{'='*60}")
        
        total_tests = len(self.test_results)
        passed = sum(1 for r in self.test_results.values() if r['status'] == 'PASSED')
        failed = sum(1 for r in self.test_results.values() if r['status'] == 'FAILED')
        errors = sum(1 for r in self.test_results.values() if r['status'] == 'ERROR')
        timeouts = sum(1 for r in self.test_results.values() if r['status'] == 'TIMEOUT')
        
        print(f"Total test files: {total_tests}")
        print(f"✅ Passed: {passed}")
        print(f"❌ Failed: {failed}")
        print(f"💥 Errors: {errors}")
        print(f"⏰ Timeouts: {timeouts}")
        
        total_duration = sum(r.get('duration', 0) for r in self.test_results.values())
        print(f"⏱️  Total duration: {total_duration:.2f}s")
        
        if failed > 0 or errors > 0 or timeouts > 0:
            print(f"\n❌ FAILED TESTS:")
            for test_file, result in self.test_results.items():
                if result['status'] != 'PASSED':
                    print(f"  - {test_file}: {result['status']}")
                    if 'error' in result:
                        print(f"    Error: {result['error'][:200]}...")
        
        success_rate = passed / total_tests if total_tests > 0 else 0
        print(f"\n📊 Success rate: {success_rate:.1%}")
        
        if success_rate >= 0.8:
            print("🎉 Overall result: GOOD")
        elif success_rate >= 0.6:
            print("⚠️  Overall result: ACCEPTABLE")
        else:
            print("🚨 Overall result: NEEDS ATTENTION")


def main():
    """Main entry point"""
    runner = CPCTestRunner()
    
    if len(sys.argv) > 1:
        if sys.argv[1] == 'quick':
            runner.quick_tests()
        elif sys.argv[1] == 'functional':
            runner.functional_tests()
        elif sys.argv[1] == 'performance':
            runner.run_performance_tests()
        elif sys.argv[1] == 'all':
            runner.run_all_tests()
        else:
            print("Usage: python run_tests.py [quick|functional|performance|all]")
            print("Default: quick")
            return
    else:
        runner.quick_tests()
    
    runner.print_summary()
    
    # Exit with error code if tests failed
    failed_count = sum(1 for r in runner.test_results.values() if r['status'] != 'PASSED')
    sys.exit(1 if failed_count > 0 else 0)


if __name__ == '__main__':
    main()
