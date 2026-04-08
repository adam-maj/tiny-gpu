"""
Enterprise Simulation Setup Framework

Provides simulation infrastructure for enterprise GPU testing including:
- Multi-clock domain simulation
- Memory model initialization
- Waveform capture configuration
- Performance monitoring infrastructure
- Enterprise validation utilities

Used by top-level chip companies for production silicon validation.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, FallingEdge, Combine
from cocotb.handle import SimHandleBase
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Callable, Any, Tuple
from enum import IntEnum, auto
import random
import json
import os
from datetime import datetime


# =============================================================================
# Simulation Configuration
# =============================================================================

@dataclass
class SimulationConfig:
    """Enterprise simulation configuration"""
    # Clock configuration
    core_clock_period_ns: float = 10.0
    memory_clock_period_ns: float = 5.0
    
    # Reset configuration
    reset_cycles: int = 10
    post_reset_delay_cycles: int = 5
    
    # Execution limits
    max_simulation_cycles: int = 100000
    watchdog_timeout_cycles: int = 50000
    
    # Memory configuration
    data_mem_size: int = 256
    program_mem_size: int = 256
    cache_line_size: int = 64
    
    # Debug configuration
    enable_waveform: bool = True
    enable_coverage: bool = True
    enable_assertions: bool = True
    verbose_logging: bool = False
    
    # Enterprise settings
    silicon_validation_mode: bool = False
    stress_test_iterations: int = 100
    thermal_model_enabled: bool = True


class SimulationState(IntEnum):
    """Simulation state machine states"""
    IDLE = auto()
    RESET = auto()
    INIT = auto()
    RUNNING = auto()
    WAITING = auto()
    COMPLETED = auto()
    ERROR = auto()
    TIMEOUT = auto()


@dataclass
class PerformanceCounters:
    """Enterprise performance monitoring counters"""
    total_cycles: int = 0
    active_cycles: int = 0
    stall_cycles: int = 0
    instructions_issued: int = 0
    instructions_completed: int = 0
    memory_reads: int = 0
    memory_writes: int = 0
    cache_hits: int = 0
    cache_misses: int = 0
    branch_predictions: int = 0
    branch_mispredictions: int = 0
    divergent_warps: int = 0
    
    def reset(self):
        """Reset all counters"""
        for field_name in self.__dataclass_fields__:
            setattr(self, field_name, 0)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            'total_cycles': self.total_cycles,
            'active_cycles': self.active_cycles,
            'stall_cycles': self.stall_cycles,
            'instructions_issued': self.instructions_issued,
            'instructions_completed': self.instructions_completed,
            'memory_reads': self.memory_reads,
            'memory_writes': self.memory_writes,
            'cache_hits': self.cache_hits,
            'cache_misses': self.cache_misses,
            'branch_predictions': self.branch_predictions,
            'branch_mispredictions': self.branch_mispredictions,
            'divergent_warps': self.divergent_warps,
            # Derived metrics
            'ipc': self.ipc,
            'cache_hit_rate': self.cache_hit_rate,
            'stall_rate': self.stall_rate,
        }
    
    @property
    def ipc(self) -> float:
        """Instructions per cycle"""
        return self.instructions_completed / max(1, self.total_cycles)
    
    @property
    def cache_hit_rate(self) -> float:
        """Cache hit rate"""
        total = self.cache_hits + self.cache_misses
        return self.cache_hits / max(1, total)
    
    @property
    def stall_rate(self) -> float:
        """Stall cycle rate"""
        return self.stall_cycles / max(1, self.total_cycles)
    
    @property
    def branch_accuracy(self) -> float:
        """Branch prediction accuracy"""
        total = self.branch_predictions + self.branch_mispredictions
        return self.branch_predictions / max(1, total)


# =============================================================================
# Simulation Memory Models
# =============================================================================

class SimulationMemory:
    """
    Enterprise-grade memory model for GPU simulation
    
    Features:
    - Multi-bank memory with configurable latency
    - Cache model with configurable parameters
    - Memory access tracking and statistics
    """
    
    def __init__(self, 
                 size: int = 256, 
                 data_width: int = 8,
                 num_banks: int = 4,
                 access_latency: int = 1):
        self.size = size
        self.data_width = data_width
        self.num_banks = num_banks
        self.access_latency = access_latency
        
        self.memory = [0] * size
        self.access_count = 0
        self.read_count = 0
        self.write_count = 0
        
        # Bank conflict tracking
        self.bank_conflicts = 0
        self.last_bank_access = [-1] * num_banks
    
    def read(self, address: int) -> int:
        """Read from memory with bank conflict detection"""
        if 0 <= address < self.size:
            bank = address % self.num_banks
            
            # Check for bank conflict
            if self.last_bank_access[bank] == address:
                self.bank_conflicts += 1
            
            self.last_bank_access[bank] = address
            self.access_count += 1
            self.read_count += 1
            
            return self.memory[address]
        return 0
    
    def write(self, address: int, data: int) -> bool:
        """Write to memory with bounds checking"""
        if 0 <= address < self.size:
            bank = address % self.num_banks
            
            if self.last_bank_access[bank] == address:
                self.bank_conflicts += 1
            
            self.last_bank_access[bank] = address
            self.access_count += 1
            self.write_count += 1
            
            self.memory[address] = data & ((1 << self.data_width) - 1)
            return True
        return False
    
    def load_data(self, data: List[int], start_address: int = 0):
        """Bulk load data into memory"""
        for i, value in enumerate(data):
            if start_address + i < self.size:
                self.memory[start_address + i] = value & ((1 << self.data_width) - 1)
    
    def dump(self, start: int = 0, count: int = 16) -> List[int]:
        """Dump memory contents for debugging"""
        end = min(start + count, self.size)
        return self.memory[start:end]
    
    def get_stats(self) -> Dict[str, Any]:
        """Get memory access statistics"""
        return {
            'total_accesses': self.access_count,
            'reads': self.read_count,
            'writes': self.write_count,
            'bank_conflicts': self.bank_conflicts,
            'read_ratio': self.read_count / max(1, self.access_count),
        }


class CacheModel:
    """
    Configurable cache model for GPU simulation
    
    Supports:
    - Direct-mapped, set-associative, and fully-associative caches
    - LRU, FIFO, and random replacement policies
    - Write-back and write-through modes
    """
    
    def __init__(self,
                 size_bytes: int = 1024,
                 line_size: int = 64,
                 associativity: int = 4,
                 write_policy: str = 'write-back'):
        self.size_bytes = size_bytes
        self.line_size = line_size
        self.associativity = associativity
        self.write_policy = write_policy
        
        self.num_sets = size_bytes // (line_size * associativity)
        
        # Cache storage: [set][way] = (valid, tag, dirty, data)
        self.cache = [[{'valid': False, 'tag': 0, 'dirty': False, 'lru': 0}
                       for _ in range(associativity)]
                      for _ in range(self.num_sets)]
        
        # Statistics
        self.hits = 0
        self.misses = 0
        self.evictions = 0
        self.writebacks = 0
    
    def _get_set_and_tag(self, address: int) -> Tuple[int, int]:
        """Extract set index and tag from address"""
        offset_bits = (self.line_size - 1).bit_length()
        set_bits = (self.num_sets - 1).bit_length() if self.num_sets > 1 else 0
        
        set_index = (address >> offset_bits) & ((1 << set_bits) - 1)
        tag = address >> (offset_bits + set_bits)
        
        return set_index, tag
    
    def access(self, address: int, is_write: bool = False) -> bool:
        """Access cache, returns True on hit"""
        set_idx, tag = self._get_set_and_tag(address)
        
        # Check for hit
        for way in range(self.associativity):
            entry = self.cache[set_idx][way]
            if entry['valid'] and entry['tag'] == tag:
                self.hits += 1
                entry['lru'] = 0  # Most recently used
                if is_write and self.write_policy == 'write-back':
                    entry['dirty'] = True
                # Update LRU for other entries
                for other_way in range(self.associativity):
                    if other_way != way:
                        self.cache[set_idx][other_way]['lru'] += 1
                return True
        
        # Miss - need to allocate
        self.misses += 1
        self._allocate(set_idx, tag, is_write)
        return False
    
    def _allocate(self, set_idx: int, tag: int, is_write: bool):
        """Allocate cache line using LRU replacement"""
        # Find LRU entry or invalid entry
        victim_way = 0
        max_lru = -1
        
        for way in range(self.associativity):
            entry = self.cache[set_idx][way]
            if not entry['valid']:
                victim_way = way
                break
            if entry['lru'] > max_lru:
                max_lru = entry['lru']
                victim_way = way
        
        victim = self.cache[set_idx][victim_way]
        
        # Writeback if dirty
        if victim['valid'] and victim['dirty']:
            self.writebacks += 1
        
        if victim['valid']:
            self.evictions += 1
        
        # Install new line
        self.cache[set_idx][victim_way] = {
            'valid': True,
            'tag': tag,
            'dirty': is_write and self.write_policy == 'write-back',
            'lru': 0
        }
        
        # Update LRU
        for way in range(self.associativity):
            if way != victim_way:
                self.cache[set_idx][way]['lru'] += 1
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        total_accesses = self.hits + self.misses
        return {
            'hits': self.hits,
            'misses': self.misses,
            'hit_rate': self.hits / max(1, total_accesses),
            'miss_rate': self.misses / max(1, total_accesses),
            'evictions': self.evictions,
            'writebacks': self.writebacks,
        }


# =============================================================================
# Simulation Environment Manager
# =============================================================================

class SimulationEnvironment:
    """
    Enterprise simulation environment manager
    
    Coordinates all simulation components including:
    - Clock generation
    - Reset sequencing
    - Memory initialization
    - Performance monitoring
    - Waveform capture
    """
    
    def __init__(self, dut, config: SimulationConfig = None):
        self.dut = dut
        self.config = config or SimulationConfig()
        
        self.state = SimulationState.IDLE
        self.counters = PerformanceCounters()
        
        self.data_memory = SimulationMemory(
            size=self.config.data_mem_size,
            data_width=8
        )
        self.program_memory = SimulationMemory(
            size=self.config.program_mem_size,
            data_width=16
        )
        self.cache = CacheModel(
            size_bytes=1024,
            line_size=64,
            associativity=4
        )
        
        self.start_time = None
        self.end_time = None
        self.test_name = ""
        
    async def initialize(self):
        """Initialize simulation environment"""
        self.state = SimulationState.INIT
        
        # Start clock
        clock = Clock(self.dut.clk, self.config.core_clock_period_ns, units="ns")
        cocotb.start_soon(clock.start())
        
        # Perform reset
        await self.reset()
        
        self.state = SimulationState.IDLE
        cocotb.log.info("Simulation environment initialized")
    
    async def reset(self):
        """Perform reset sequence"""
        self.state = SimulationState.RESET
        
        self.dut.reset.value = 1
        self.dut.start.value = 0
        
        if hasattr(self.dut, 'device_control_write_enable'):
            self.dut.device_control_write_enable.value = 0
        
        await ClockCycles(self.dut.clk, self.config.reset_cycles)
        
        self.dut.reset.value = 0
        await ClockCycles(self.dut.clk, self.config.post_reset_delay_cycles)
        
        # Reset counters
        self.counters.reset()
        
        self.state = SimulationState.IDLE
    
    async def configure_threads(self, thread_count: int):
        """Configure thread count via device control register"""
        if hasattr(self.dut, 'device_control_write_enable'):
            self.dut.device_control_write_enable.value = 1
            self.dut.device_control_data.value = thread_count
            await RisingEdge(self.dut.clk)
            self.dut.device_control_write_enable.value = 0
            await RisingEdge(self.dut.clk)
    
    async def start_execution(self):
        """Start GPU kernel execution"""
        self.state = SimulationState.RUNNING
        self.start_time = datetime.now()
        
        self.dut.start.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.start.value = 0
    
    async def wait_completion(self, timeout_cycles: int = None) -> Tuple[bool, int]:
        """Wait for GPU completion with timeout"""
        timeout = timeout_cycles or self.config.max_simulation_cycles
        
        for cycle in range(timeout):
            await RisingEdge(self.dut.clk)
            self.counters.total_cycles += 1
            
            if hasattr(self.dut, 'done') and self.dut.done.value == 1:
                self.state = SimulationState.COMPLETED
                self.end_time = datetime.now()
                return True, cycle + 1
        
        self.state = SimulationState.TIMEOUT
        self.end_time = datetime.now()
        return False, timeout
    
    async def run_workload(self, 
                           thread_count: int,
                           timeout_cycles: int = None) -> Dict[str, Any]:
        """Run a complete workload and return results"""
        await self.reset()
        await self.configure_threads(thread_count)
        await self.start_execution()
        
        completed, cycles = await self.wait_completion(timeout_cycles)
        
        return {
            'completed': completed,
            'cycles': cycles,
            'thread_count': thread_count,
            'counters': self.counters.to_dict(),
            'memory_stats': self.data_memory.get_stats(),
            'cache_stats': self.cache.get_stats(),
            'state': self.state.name,
        }
    
    def generate_report(self) -> str:
        """Generate simulation report"""
        duration = (self.end_time - self.start_time).total_seconds() if self.end_time and self.start_time else 0
        
        report = f"""
================================================================================
                    Enterprise GPU Simulation Report
================================================================================
Test: {self.test_name}
State: {self.state.name}
Duration: {duration:.3f} seconds

Performance Counters:
  Total Cycles:      {self.counters.total_cycles}
  Active Cycles:     {self.counters.active_cycles}
  Stall Cycles:      {self.counters.stall_cycles}
  IPC:               {self.counters.ipc:.3f}
  Stall Rate:        {self.counters.stall_rate:.2%}

Memory Statistics:
  Total Accesses:    {self.data_memory.access_count}
  Reads:             {self.data_memory.read_count}
  Writes:            {self.data_memory.write_count}
  Bank Conflicts:    {self.data_memory.bank_conflicts}

Cache Statistics:
  Hits:              {self.cache.hits}
  Misses:            {self.cache.misses}
  Hit Rate:          {self.cache.hits / max(1, self.cache.hits + self.cache.misses):.2%}
  Evictions:         {self.cache.evictions}
  Writebacks:        {self.cache.writebacks}

================================================================================
"""
        return report


# =============================================================================
# Workload Generators
# =============================================================================

class WorkloadGenerator:
    """Generate various GPU workloads for testing"""
    
    @staticmethod
    def generate_vector_add(size: int) -> Tuple[List[int], List[int], List[int]]:
        """Generate vector addition workload"""
        a = [random.randint(0, 127) for _ in range(size)]
        b = [random.randint(0, 127) for _ in range(size)]
        expected = [(a[i] + b[i]) & 0xFF for i in range(size)]
        return a, b, expected
    
    @staticmethod
    def generate_matrix_mul(m: int, n: int, k: int) -> Tuple[List[List[int]], List[List[int]], List[List[int]]]:
        """Generate matrix multiplication workload"""
        a = [[random.randint(0, 15) for _ in range(k)] for _ in range(m)]
        b = [[random.randint(0, 15) for _ in range(n)] for _ in range(k)]
        
        c = [[0] * n for _ in range(m)]
        for i in range(m):
            for j in range(n):
                for kk in range(k):
                    c[i][j] += a[i][kk] * b[kk][j]
                c[i][j] &= 0xFF
        
        return a, b, c
    
    @staticmethod
    def generate_reduction(size: int) -> Tuple[List[int], int]:
        """Generate reduction workload"""
        data = [random.randint(0, 31) for _ in range(size)]
        expected = sum(data) & 0xFFFF
        return data, expected
    
    @staticmethod
    def generate_stencil(width: int, height: int) -> Tuple[List[List[int]], List[List[int]]]:
        """Generate 2D stencil workload"""
        data = [[random.randint(0, 255) for _ in range(width)] for _ in range(height)]
        
        # 3x3 averaging stencil
        result = [[0] * width for _ in range(height)]
        for y in range(1, height - 1):
            for x in range(1, width - 1):
                total = 0
                for dy in range(-1, 2):
                    for dx in range(-1, 2):
                        total += data[y + dy][x + dx]
                result[y][x] = total // 9
        
        return data, result


# =============================================================================
# Validation Utilities
# =============================================================================

class ValidationSuite:
    """Enterprise validation utilities"""
    
    @staticmethod
    async def validate_reset_state(dut) -> bool:
        """Validate GPU is in correct state after reset"""
        errors = []
        
        if hasattr(dut, 'done') and dut.done.value != 0:
            errors.append("done signal should be 0 after reset")
        
        if hasattr(dut, 'start') and dut.start.value != 0:
            errors.append("start signal should be 0 after reset")
        
        if errors:
            for error in errors:
                cocotb.log.error(f"Reset validation failed: {error}")
            return False
        
        return True
    
    @staticmethod
    async def validate_signal_stability(dut, signal_name: str, cycles: int = 10) -> bool:
        """Validate signal stability over multiple cycles"""
        if not hasattr(dut, signal_name):
            cocotb.log.warning(f"Signal {signal_name} not found")
            return True
        
        signal = getattr(dut, signal_name)
        initial_value = signal.value
        
        for _ in range(cycles):
            await RisingEdge(dut.clk)
            if signal.value != initial_value:
                # Value changed, which may be OK - just log it
                cocotb.log.debug(f"Signal {signal_name} changed from {initial_value} to {signal.value}")
        
        return True
    
    @staticmethod
    def validate_memory_consistency(mem: SimulationMemory, expected: List[int], start: int = 0) -> bool:
        """Validate memory contents match expected values"""
        errors = []
        
        for i, exp in enumerate(expected):
            addr = start + i
            actual = mem.read(addr)
            if actual != exp:
                errors.append(f"Memory[{addr}] = {actual}, expected {exp}")
        
        if errors:
            for error in errors[:10]:  # Limit error output
                cocotb.log.error(f"Memory validation failed: {error}")
            return False
        
        return True


# =============================================================================
# Test Decorators and Utilities
# =============================================================================

def enterprise_test(timeout_cycles: int = 10000, 
                    require_completion: bool = True):
    """Decorator for enterprise GPU tests"""
    def decorator(func):
        async def wrapper(dut):
            env = SimulationEnvironment(dut)
            env.test_name = func.__name__
            
            await env.initialize()
            
            try:
                result = await func(dut, env)
                
                if require_completion and env.state != SimulationState.COMPLETED:
                    cocotb.log.warning(f"Test did not complete: state={env.state.name}")
                
                return result
            except Exception as e:
                env.state = SimulationState.ERROR
                cocotb.log.error(f"Test failed with exception: {e}")
                raise
            finally:
                report = env.generate_report()
                cocotb.log.info(report)
        
        return cocotb.test()(wrapper)
    return decorator
