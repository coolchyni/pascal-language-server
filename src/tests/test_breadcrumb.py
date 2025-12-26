#!/usr/bin/env python3
"""
Test script for LSP DocumentSymbol breadcrumb functionality.

This script tests the Pascal Language Server's hierarchical DocumentSymbol
support by verifying that the breadcrumb path is correct for various
cursor positions in test_symbols.pas.
"""

import json
import subprocess
import sys
import os
from pathlib import Path
from typing import Optional

# Path configuration
SCRIPT_DIR = Path(__file__).parent
PASLS_EXE = SCRIPT_DIR.parent / "standard" / "lib" / "i386-win32" / "pasls.exe"
TEST_FILE = SCRIPT_DIR / "test_symbols.pas"
TEST_PROGRAM_FILE = SCRIPT_DIR / "test_program.lpr"


class LSPClient:
    """Simple LSP client for testing."""

    def __init__(self, server_path: str):
        self.server_path = server_path
        self.process: Optional[subprocess.Popen] = None
        self.request_id = 0

    def start(self):
        """Start the LSP server."""
        self.process = subprocess.Popen(
            [str(self.server_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def stop(self):
        """Stop the LSP server."""
        if self.process:
            self.process.terminate()
            self.process.wait()

    def send_request(self, method: str, params: dict) -> dict:
        """Send an LSP request and wait for response."""
        self.request_id += 1
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": method,
            "params": params
        }
        return self._send_message(request)

    def send_notification(self, method: str, params: dict):
        """Send an LSP notification (no response expected)."""
        notification = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        }
        self._write_message(notification)

    def _write_message(self, message: dict):
        """Write a message to the server."""
        content = json.dumps(message)
        header = f"Content-Length: {len(content)}\r\n\r\n"
        self.process.stdin.write(header.encode('utf-8'))
        self.process.stdin.write(content.encode('utf-8'))
        self.process.stdin.flush()

    def _read_message(self) -> dict:
        """Read a message from the server."""
        # Read headers
        headers = {}
        while True:
            line = self.process.stdout.readline().decode('utf-8')
            if line == '\r\n' or line == '\n':
                break
            if ':' in line:
                key, value = line.split(':', 1)
                headers[key.strip()] = value.strip()

        # Read content
        content_length = int(headers.get('Content-Length', 0))
        if content_length > 0:
            content = self.process.stdout.read(content_length).decode('utf-8')
            return json.loads(content)
        return {}

    def _send_message(self, message: dict) -> dict:
        """Send a message and read response."""
        self._write_message(message)

        # Read responses until we get one matching our request id
        while True:
            response = self._read_message()
            if response.get('id') == message.get('id'):
                return response
            # Skip notifications


def find_outline_path(symbols: list, line: int, parent_path: list = None) -> list:
    """
    Find the outline path for a given line number (for Outline view testing).

    This uses parent-child relationships regardless of range containment.
    In Pascal, class declarations and method implementations are separate,
    so we search all children regardless of parent range.
    """
    if parent_path is None:
        parent_path = []

    best_match = None
    best_match_size = float('inf')  # Smaller range = more specific match

    for symbol in symbols:
        start_line = symbol['range']['start']['line']
        end_line = symbol['range']['end']['line']
        current_path = parent_path + [symbol['name']]

        # Always check children first (they might contain the line even if parent doesn't)
        children = symbol.get('children', [])
        if children:
            child_path = find_outline_path(children, line, current_path)
            if child_path and len(child_path) > len(current_path):
                # Found a match in children
                child_symbol = None
                for c in children:
                    if c['name'] == child_path[len(current_path)]:
                        child_symbol = c
                        break
                if child_symbol:
                    child_size = child_symbol['range']['end']['line'] - child_symbol['range']['start']['line']
                    if child_size < best_match_size:
                        best_match = child_path
                        best_match_size = child_size

        # Check if line is within this symbol's range
        if start_line <= line <= end_line:
            range_size = end_line - start_line
            if range_size < best_match_size:
                best_match = current_path
                best_match_size = range_size

    return best_match


def find_breadcrumb_by_range(symbols: list, line: int) -> list:
    """
    Find the breadcrumb path based on range containment only (VS Code behavior).

    VS Code shows breadcrumb based on which symbol ranges contain the cursor.
    This traverses the symbol tree hierarchy directly, building a chain of
    symbols whose ranges contain the line.

    Note: This handles duplicate symbol names correctly by using the actual
    tree structure rather than flattening and matching by name path.
    """
    def find_containing_path(symbols_list, target_line):
        """Recursively find the deepest path of symbols containing the line."""
        for symbol in symbols_list:
            start_line = symbol['range']['start']['line']
            end_line = symbol['range']['end']['line']

            if start_line <= target_line <= end_line:
                # This symbol contains the line, start building path
                path = [symbol['name']]

                # Check children for a more specific (deeper) match
                children = symbol.get('children', [])
                if children:
                    child_path = find_containing_path(children, target_line)
                    if child_path:
                        path.extend(child_path)

                return path

        return None

    # Try each top-level symbol and find the longest matching path
    best_result = None

    for symbol in symbols:
        result = find_containing_path([symbol], line)
        if result and (best_result is None or len(result) > len(best_result)):
            best_result = result

    return best_result


def run_tests():
    """Run all tests for Outline and Breadcrumb functionality."""

    # Test cases: (line_number, expected_path, is_critical)
    # Line numbers are 1-based (will be converted to 0-based for LSP)
    # is_critical: True = must pass for overall success, False = known limitation
    #
    # F1 Scheme: Interface and Implementation as namespaces
    # - Interface section: class declarations → interface > ClassName
    # - Implementation section: method implementations → implementation > ClassName > MethodName
    # - Implementation section: global functions → implementation > FunctionName
    test_cases = [
        # Type declarations in interface section - CRITICAL
        (22, ['interface', 'TTestClassA'], True),  # Inside TTestClassA declaration
        (32, ['interface', 'TTestClassB'], True),  # Inside TTestClassB declaration
        (41, ['interface', 'TTestRecord'], True),  # Inside TTestRecord

        # Global function declarations in interface section - CRITICAL
        (45, ['interface', 'GlobalFunction1'], True),  # GlobalFunction1 declaration
        (46, ['interface', 'GlobalFunction2'], True),  # GlobalFunction2 declaration

        # Class methods (implementation section) - CRITICAL
        # F1 Scheme: implementation > ClassName > MethodName
        (77, ['implementation', 'TTestClassA', 'MethodA1'], True),  # Test point 1: inside MethodA1
        (84, ['implementation', 'TTestClassA', 'MethodA2'], True),  # Test point 2: inside MethodA2
        (90, ['implementation', 'TTestClassA', 'MethodA3'], True),  # Test point 3: inside MethodA3
        (98, ['implementation', 'TTestClassB', 'MethodB1'], True),  # Test point 4: inside MethodB1
        (104, ['implementation', 'TTestClassB', 'MethodB2'], True), # Test point 5: inside MethodB2

        # Nested functions in class methods - CRITICAL
        (59, ['implementation', 'TTestClassA', 'MethodA1', 'NestedProc1'], True),  # Inside NestedProc1
        (72, ['implementation', 'TTestClassA', 'MethodA1', 'NestedFunc2'], True),  # Inside NestedFunc2
        (68, ['implementation', 'TTestClassA', 'MethodA1', 'NestedFunc2', 'DeeplyNested'], True),  # Inside DeeplyNested

        # Global functions - under Implementation namespace (F1 scheme)
        (117, ['implementation', 'GlobalFunction1', 'NestedInGlobal'], True),  # Inside NestedInGlobal
        (121, ['implementation', 'GlobalFunction1'], True),  # Test point 6: inside GlobalFunction1
        (127, ['implementation', 'GlobalFunction2'], True),  # Test point 7: inside GlobalFunction2
    ]

    print("=" * 70)
    print("LSP DocumentSymbol Test (Outline & Breadcrumb)")
    print("=" * 70)
    print(f"Server: {PASLS_EXE}")
    print(f"Test file: {TEST_FILE}")
    print()

    # Check if server exists
    if not PASLS_EXE.exists():
        print(f"ERROR: Server not found: {PASLS_EXE}")
        return False

    if not TEST_FILE.exists():
        print(f"ERROR: Test file not found: {TEST_FILE}")
        return False

    # Start LSP client
    client = LSPClient(str(PASLS_EXE))

    try:
        print("Starting LSP server...")
        client.start()

        # Initialize
        print("Sending initialize request...")
        init_response = client.send_request("initialize", {
            "processId": os.getpid(),
            "capabilities": {
                "textDocument": {
                    "documentSymbol": {
                        "hierarchicalDocumentSymbolSupport": True
                    }
                }
            },
            "rootUri": f"file:///{TEST_FILE.parent.as_posix()}",
            "workspaceFolders": None
        })

        if 'error' in init_response:
            print(f"ERROR: Initialize failed: {init_response['error']}")
            return False

        # Send initialized notification
        client.send_notification("initialized", {})

        # Open document
        print("Opening test document...")
        with open(TEST_FILE, 'r', encoding='utf-8') as f:
            content = f.read()

        file_uri = f"file:///{TEST_FILE.as_posix()}"
        client.send_notification("textDocument/didOpen", {
            "textDocument": {
                "uri": file_uri,
                "languageId": "pascal",
                "version": 1,
                "text": content
            }
        })

        # Get document symbols
        print("Requesting document symbols...")
        symbols_response = client.send_request("textDocument/documentSymbol", {
            "textDocument": {
                "uri": file_uri
            }
        })

        if 'error' in symbols_response:
            print(f"ERROR: documentSymbol failed: {symbols_response['error']}")
            return False

        symbols = symbols_response.get('result', [])

        if not symbols:
            print("ERROR: No symbols returned")
            return False

        print(f"Received {len(symbols)} top-level symbols")
        print()

        # Print symbol tree for debugging
        print("Symbol tree:")
        print("-" * 40)
        print_symbol_tree(symbols)
        print("-" * 40)
        print()

        # ==================== OUTLINE TESTS ====================
        print("=" * 70)
        print("OUTLINE TESTS (parent-child hierarchy)")
        print("=" * 70)

        outline_passed = 0
        outline_failed = 0
        outline_critical_failed = 0

        for line, expected, is_critical in test_cases:
            lsp_line = line - 1
            actual = find_outline_path(symbols, lsp_line)

            if actual == expected:
                status = "PASS"
                outline_passed += 1
            else:
                status = "FAIL" if is_critical else "WARN"
                outline_failed += 1
                if is_critical:
                    outline_critical_failed += 1

            expected_str = " > ".join(expected) if expected else "(none)"
            actual_str = " > ".join(actual) if actual else "(none)"

            print(f"Line {line:3d}: {status}")
            print(f"  Expected: {expected_str}")
            print(f"  Actual:   {actual_str}")
            if status == "FAIL":
                print(f"  *** CRITICAL MISMATCH ***")
            elif status == "WARN":
                print(f"  (known limitation)")
            print()

        print("-" * 70)
        print(f"Outline Results: {outline_passed} passed, {outline_failed} failed ({outline_critical_failed} critical)")

        # ==================== BREADCRUMB TESTS ====================
        print()
        print("=" * 70)
        print("BREADCRUMB TESTS (range containment - VS Code behavior)")
        print("=" * 70)

        breadcrumb_passed = 0
        breadcrumb_failed = 0
        breadcrumb_critical_failed = 0

        for line, expected, is_critical in test_cases:
            lsp_line = line - 1
            actual = find_breadcrumb_by_range(symbols, lsp_line)

            if actual == expected:
                status = "PASS"
                breadcrumb_passed += 1
            else:
                status = "FAIL" if is_critical else "WARN"
                breadcrumb_failed += 1
                if is_critical:
                    breadcrumb_critical_failed += 1

            expected_str = " > ".join(expected) if expected else "(none)"
            actual_str = " > ".join(actual) if actual else "(none)"

            print(f"Line {line:3d}: {status}")
            print(f"  Expected: {expected_str}")
            print(f"  Actual:   {actual_str}")
            if status == "FAIL":
                print(f"  *** CRITICAL MISMATCH ***")
            elif status == "WARN":
                print(f"  (known limitation)")
            print()

        print("-" * 70)
        print(f"Breadcrumb Results: {breadcrumb_passed} passed, {breadcrumb_failed} failed ({breadcrumb_critical_failed} critical)")

        # ==================== SUMMARY ====================
        print()
        print("=" * 70)
        print("SUMMARY")
        print("=" * 70)
        print(f"Outline:    {outline_passed}/{len(test_cases)} passed ({outline_critical_failed} critical failures)")
        print(f"Breadcrumb: {breadcrumb_passed}/{len(test_cases)} passed ({breadcrumb_critical_failed} critical failures)")
        if outline_critical_failed == 0 and breadcrumb_critical_failed == 0:
            print("All critical tests PASSED!")
        print("=" * 70)

        # Only critical failures count for overall success
        return outline_critical_failed == 0 and breadcrumb_critical_failed == 0

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        print("Stopping LSP server...")
        client.stop()


def print_symbol_tree(symbols: list, indent: int = 0):
    """Print the symbol tree for debugging."""
    for symbol in symbols:
        name = symbol['name']
        kind = symbol.get('kind', '?')
        start = symbol['range']['start']['line'] + 1
        end = symbol['range']['end']['line'] + 1
        print(f"{'  ' * indent}{name} (kind={kind}, lines {start}-{end})")

        children = symbol.get('children', [])
        if children:
            print_symbol_tree(children, indent + 1)


def run_program_tests():
    """Run tests for program files (.lpr/.dpr) without interface/implementation."""

    # Test cases for program files: (line_number, expected_path, is_critical)
    # In program files, there are no interface/implementation namespaces
    # F1 Scheme: Two symbols per class - declaration + implementation container
    test_cases = [
        # Type declarations - CRITICAL
        (18, ['TTestClass'], True),   # Inside TTestClass declaration
        (27, ['TTestClass2'], True),  # Inside TTestClass2 declaration
        (35, ['TTestRecord'], True),  # Inside TTestRecord declaration

        # TTestClass methods - CRITICAL (under TTestClass implementation container)
        (50, ['TTestClass', 'TestMethod1'], True),  # Inside TestMethod1
        (56, ['TTestClass', 'TestMethod2'], True),  # Inside TestMethod2

        # Nested function in TTestClass method - CRITICAL
        (46, ['TTestClass', 'TestMethod1', 'NestedProc'], True),  # Inside NestedProc

        # TTestClass2 methods - CRITICAL (under TTestClass2 implementation container)
        (64, ['TTestClass2', 'MethodA'], True),  # Inside MethodA
        (78, ['TTestClass2', 'MethodB'], True),  # Inside MethodB

        # Nested function in TTestClass2 method - CRITICAL
        (74, ['TTestClass2', 'MethodB', 'NestedFunc'], True),  # Inside NestedFunc

        # Global functions - CRITICAL
        (95, ['GlobalProc'], True),   # Inside GlobalProc
        (101, ['GlobalFunc'], True),  # Inside GlobalFunc

        # Nested function in global function - CRITICAL
        (91, ['GlobalProc', 'NestedInGlobal'], True),  # Inside NestedInGlobal
    ]

    print("=" * 70)
    print("LSP DocumentSymbol Test - PROGRAM FILES (.lpr/.dpr)")
    print("=" * 70)
    print(f"Server: {PASLS_EXE}")
    print(f"Test file: {TEST_PROGRAM_FILE}")
    print()

    # Check if server exists
    if not PASLS_EXE.exists():
        print(f"ERROR: Server not found: {PASLS_EXE}")
        return False

    if not TEST_PROGRAM_FILE.exists():
        print(f"ERROR: Test file not found: {TEST_PROGRAM_FILE}")
        return False

    # Start LSP client
    client = LSPClient(str(PASLS_EXE))

    try:
        print("Starting LSP server...")
        client.start()

        # Initialize
        print("Sending initialize request...")
        init_response = client.send_request("initialize", {
            "processId": os.getpid(),
            "capabilities": {
                "textDocument": {
                    "documentSymbol": {
                        "hierarchicalDocumentSymbolSupport": True
                    }
                }
            },
            "rootUri": f"file:///{TEST_PROGRAM_FILE.parent.as_posix()}",
            "workspaceFolders": None
        })

        if 'error' in init_response:
            print(f"ERROR: Initialize failed: {init_response['error']}")
            return False

        # Send initialized notification
        client.send_notification("initialized", {})

        # Open document
        print("Opening test document...")
        with open(TEST_PROGRAM_FILE, 'r', encoding='utf-8') as f:
            content = f.read()

        file_uri = f"file:///{TEST_PROGRAM_FILE.as_posix()}"
        client.send_notification("textDocument/didOpen", {
            "textDocument": {
                "uri": file_uri,
                "languageId": "pascal",
                "version": 1,
                "text": content
            }
        })

        # Get document symbols
        print("Requesting document symbols...")
        symbols_response = client.send_request("textDocument/documentSymbol", {
            "textDocument": {
                "uri": file_uri
            }
        })

        if 'error' in symbols_response:
            print(f"ERROR: documentSymbol failed: {symbols_response['error']}")
            return False

        symbols = symbols_response.get('result', [])

        if not symbols:
            print("ERROR: No symbols returned")
            return False

        print(f"Received {len(symbols)} top-level symbols")
        print()

        # Print symbol tree for debugging
        print("Symbol tree:")
        print("-" * 40)
        print_symbol_tree(symbols)
        print("-" * 40)
        print()

        # Run breadcrumb tests
        print("=" * 70)
        print("BREADCRUMB TESTS (range containment - VS Code behavior)")
        print("=" * 70)

        breadcrumb_passed = 0
        breadcrumb_failed = 0
        breadcrumb_critical_failed = 0

        for line, expected, is_critical in test_cases:
            lsp_line = line - 1
            actual = find_breadcrumb_by_range(symbols, lsp_line)

            if actual == expected:
                status = "PASS"
                breadcrumb_passed += 1
            else:
                status = "FAIL" if is_critical else "WARN"
                breadcrumb_failed += 1
                if is_critical:
                    breadcrumb_critical_failed += 1

            expected_str = " > ".join(expected) if expected else "(none)"
            actual_str = " > ".join(actual) if actual else "(none)"

            print(f"Line {line:3d}: {status}")
            print(f"  Expected: {expected_str}")
            print(f"  Actual:   {actual_str}")
            if status == "FAIL":
                print(f"  *** CRITICAL MISMATCH ***")
            elif status == "WARN":
                print(f"  (known limitation)")
            print()

        print("-" * 70)
        print(f"Breadcrumb Results: {breadcrumb_passed} passed, {breadcrumb_failed} failed ({breadcrumb_critical_failed} critical)")

        # Summary
        print()
        print("=" * 70)
        print("SUMMARY")
        print("=" * 70)
        print(f"Program file tests: {breadcrumb_passed}/{len(test_cases)} passed ({breadcrumb_critical_failed} critical failures)")
        if breadcrumb_critical_failed == 0:
            print("All critical tests PASSED!")
        print("=" * 70)

        return breadcrumb_critical_failed == 0

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        print("Stopping LSP server...")
        client.stop()


if __name__ == '__main__':
    # Run unit file tests
    success_unit = run_tests()
    print("\n\n")

    # Run program file tests
    success_program = run_program_tests()

    # Overall success if both pass
    sys.exit(0 if (success_unit and success_program) else 1)
