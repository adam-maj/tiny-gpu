from typing import List
from .logger import logger


# 这个类不是 RTL 里的 RAM 宏，而是 cocotb 测试平台里的“软件内存模型”。
# 你可以把它理解成：Python 代码在 testbench 外面假装自己是一块存储器，
# 然后通过 dut 上的读写握手信号，像真正的外设一样和 Verilog 顶层交互。
class Memory:
    # Python 里 def 用来定义函数；写在类里面时，这个函数就是“方法”。
    # __init__ 是构造函数，含义类似“创建对象时先执行的初始化逻辑”。
    # self 表示“当前这个 Memory 对象本身”，和很多语言里的 this 类似。
    def __init__(self, dut, addr_bits, data_bits, channels, name):
        # 保存 cocotb 传进来的 DUT 句柄，后面就能通过 self.dut 访问顶层信号。
        self.dut = dut
        # 保存地址位宽，例如 8 表示地址总线宽度是 8 bit，可寻址 2^8 个单元。
        self.addr_bits = addr_bits
        # 保存数据位宽，例如 8 表示每个存储单元存 8 bit 数据。
        self.data_bits = data_bits
        # Python 里的 [0] * N 表示生成一个长度为 N 的列表，并且每个元素初始值都是 0。
        # 这里用它来模拟一整块内存；2**addr_bits 就是 2 的 addr_bits 次方。
        self.memory = [0] * (2**addr_bits)
        # channels 表示并行通道数，对应 Verilog 里一次可以同时服务多少个 lane 的访存请求。
        self.channels = channels
        # name 用来区分 program memory 和 data memory，也用来拼接信号名。
        self.name = name

        # getattr(obj, "attr") 的意思是“按字符串名字，从对象 obj 身上取属性 attr”。
        # 这里配合 f"{name}_..." 这种 f-string，把 name 动态插进信号名中。
        # 例如 name="data" 时，最终会取到 dut.data_mem_read_valid 这个句柄。
        self.mem_read_valid = getattr(dut, f"{name}_mem_read_valid")
        # 读地址总线，DUT 会把想读的地址放在这个信号上。
        self.mem_read_address = getattr(dut, f"{name}_mem_read_address")
        # 读 ready 总线，由这个 Python 内存模型回填给 DUT，表示“这次读我接住了”。
        self.mem_read_ready = getattr(dut, f"{name}_mem_read_ready")
        # 读 data 总线，由这个 Python 内存模型回填给 DUT，表示“这是你读到的数据”。
        self.mem_read_data = getattr(dut, f"{name}_mem_read_data")

        # program memory 在这个工程里只读不写，所以只有 data memory 需要接写口。
        if name != "program":
            # 写 valid：DUT 置 1 表示某个 lane 正在发起写请求。
            self.mem_write_valid = getattr(dut, f"{name}_mem_write_valid")
            # 写地址：DUT 想把数据写到哪里。
            self.mem_write_address = getattr(dut, f"{name}_mem_write_address")
            # 写数据：DUT 想写进去的值。
            self.mem_write_data = getattr(dut, f"{name}_mem_write_data")
            # 写 ready：这个 Python 内存模型回给 DUT，表示“这次写我接受了”。
            self.mem_write_ready = getattr(dut, f"{name}_mem_write_ready")

    # run() 可以理解成“把这块软件内存跑一个仿真周期的组合/握手逻辑”。
    # cycle 参数不是功能必须项，只是为了写日志时能打印当前周期号。
    def run(self, cycle=None):
        # 把 cocotb 句柄里的值转成字符串，便于后面按位切片。
        # 例如多通道 valid 可能会变成 "1010" 这样的二进制字符串。
        mem_read_valid_bits = str(self.mem_read_valid.value)
        # 先创建一个空列表，后面逐个 lane 填入解析后的 valid 位。
        mem_read_valid = []
        # range(起点, 终点, 步长) 会生成一个整数序列；这里步长是 1，表示逐位扫描。
        for i in range(0, len(mem_read_valid_bits), 1):
            # Python 切片 s[a:b] 表示取下标 a 到 b 之前的内容，也就是左闭右开区间。
            bit_slice = mem_read_valid_bits[i : i + 1]
            # int(字符串, 2) 表示把二进制字符串转换成十进制整数。
            mem_read_valid.append(int(bit_slice, 2))

        # 同样先把读地址总线整体转成字符串。
        mem_read_address_bits = str(self.mem_read_address.value)
        # 创建一个空列表，准备保存每个通道各自的读地址。
        mem_read_address = []
        # 地址总线是按 addr_bits 一组拼接起来的，所以这里每次跳一个地址宽度。
        for i in range(0, len(mem_read_address_bits), self.addr_bits):
            # 取出当前 lane 对应的一段地址比特。
            address_slice = mem_read_address_bits[i : i + self.addr_bits]
            # 把二进制地址字符串转成 Python 整数，后面才能拿来做列表下标。
            mem_read_address.append(int(address_slice, 2))

        # 先默认所有 lane 都不 ready；后面谁真的请求了读，谁再被置成 1。
        mem_read_ready = [0] * self.channels
        # 先给每个 lane 准备一个返回数据槽位，默认值都是 0。
        mem_read_data = [0] * self.channels

        # 逐个通道处理读请求，这很像硬件里“for each lane”的行为。
        for i in range(self.channels):
            # 如果 valid 为 1，说明 DUT 当前周期确实发起了读请求。
            if mem_read_valid[i] == 1:
                # 用请求地址作为 Python 列表下标，从软件内存里取出对应数据。
                mem_read_data[i] = self.memory[mem_read_address[i]]
                # 返回 ready=1，告诉 DUT 这次读已经被响应。
                mem_read_ready[i] = 1
            else:
                # 如果这个 lane 没请求，就显式返回 ready=0。
                mem_read_ready[i] = 0

        # 创建一个空列表，用来存每个 lane 的数据字符串。
        mem_read_data_fields = []
        # 逐个 lane 把整数格式化成固定宽度的二进制字符串。
        for data in mem_read_data:
            # format(value, "08b") 这类写法表示输出二进制并且左侧补 0 到固定宽度。
            # 这里宽度不是写死，而是用 "0" + str(self.data_bits) + "b" 动态拼出来。
            mem_read_data_fields.append(format(data, "0" + str(self.data_bits) + "b"))
        # "".join(list) 表示把字符串列表无分隔符拼接成一个完整的大总线字符串。
        mem_read_data_bus = "".join(mem_read_data_fields)
        # 再把整个二进制字符串转回整数，赋给 cocotb 信号句柄的 .value。
        self.mem_read_data.value = int(mem_read_data_bus, 2)

        # 创建一个空列表，用来存 ready 位拼接后的字符串。
        mem_read_ready_fields = []
        # 每个 ready 只占 1 bit，所以格式字符串固定写成 01b。
        for ready in mem_read_ready:
            mem_read_ready_fields.append(format(ready, "01b"))
        # 把所有 ready 位拼成一个多通道 ready 总线。
        mem_read_ready_bus = "".join(mem_read_ready_fields)
        # 把 ready 总线写回 DUT，让 Verilog 逻辑在这个周期看到握手结果。
        self.mem_read_ready.value = int(mem_read_ready_bus, 2)

        # 只有 data memory 需要处理写请求；program memory 是只读的，不会走这段。
        if self.name != "program":
            # 先读取整条写 valid 总线，并转成字符串方便切片。
            mem_write_valid_bits = str(self.mem_write_valid.value)
            # 创建列表，准备保存每个通道的写 valid。
            mem_write_valid = []
            # 逐 bit 切开 valid 总线，因为每个通道只有 1 bit valid。
            for i in range(0, len(mem_write_valid_bits), 1):
                # 取出当前通道对应的 1 个 bit。
                bit_slice = mem_write_valid_bits[i : i + 1]
                # 转成整数 0 或 1，便于后面判断。
                mem_write_valid.append(int(bit_slice, 2))

            # 读取整条写地址总线。
            mem_write_address_bits = str(self.mem_write_address.value)
            # 创建列表，准备保存每个通道的目标地址。
            mem_write_address = []
            # 地址总线按 addr_bits 位一组切分。
            for i in range(0, len(mem_write_address_bits), self.addr_bits):
                # 取出当前通道的地址字段。
                address_slice = mem_write_address_bits[i : i + self.addr_bits]
                # 二进制字符串转整数，得到真实的地址索引。
                mem_write_address.append(int(address_slice, 2))

            # 读取整条写数据总线。
            mem_write_data_bits = str(self.mem_write_data.value)
            # 创建列表，准备保存每个通道要写入的数据。
            mem_write_data = []
            # 数据总线按 data_bits 位一组切分。
            for i in range(0, len(mem_write_data_bits), self.data_bits):
                # 取出当前通道的数据字段。
                data_slice = mem_write_data_bits[i : i + self.data_bits]
                # 把数据字段转成整数，方便写入 Python 列表。
                mem_write_data.append(int(data_slice, 2))

            # 默认所有写通道都还没有被接受。
            mem_write_ready = [0] * self.channels

            # 逐个通道处理写请求。
            for i in range(self.channels):
                # 只有 valid=1 的 lane 才真的执行写入。
                if mem_write_valid[i] == 1:
                    # 先读出旧值，后面打印日志时可以看出这次写改了什么。
                    old_data = self.memory[mem_write_address[i]]
                    # 用新值覆盖对应地址，等价于 testbench 中这块 RAM 完成一次写操作。
                    self.memory[mem_write_address[i]] = mem_write_data[i]
                    # 这里用 logger.debug 记录一次写事务，方便测试脚本回头检查写轨迹。
                    logger.debug(
                        f"[memwrite] {self.name} cycle={cycle if cycle is not None else -1} "
                        f"lane={i} addr={mem_write_address[i]} old={old_data} new={mem_write_data[i]}"
                    )
                    # 把当前 lane 的 ready 置 1，告诉 DUT 这次写已经完成握手。
                    mem_write_ready[i] = 1
                else:
                    # 没有写请求的 lane 返回 ready=0。
                    mem_write_ready[i] = 0

            # 创建列表，用来收集每个写 ready 位的字符串表示。
            mem_write_ready_fields = []
            # 每个写 ready 也只有 1 bit，所以还是格式化成 01b。
            for ready in mem_write_ready:
                mem_write_ready_fields.append(format(ready, "01b"))
            # 拼成整条写 ready 总线。
            mem_write_ready_bus = "".join(mem_write_ready_fields)
            # 把 ready 总线写回 DUT，完成本周期的写响应。
            self.mem_write_ready.value = int(mem_write_ready_bus, 2)

    # write() 是一个更底层的小工具函数，作用是“直接往软件内存某个地址写值”。
    def write(self, address, data):
        # 先检查地址是否越界，避免 Python 列表访问报错。
        if address < len(self.memory):
            # 如果地址合法，就把对应位置的数据改成新值。
            self.memory[address] = data

    # load() 用于把一串初始数据批量装进内存，常用于测试开始前预装程序或输入数据。
    def load(self, rows: List[int]):
        # enumerate(rows) 会返回 (下标, 元素) 二元组，非常适合“地址=序号，数据=内容”这种场景。
        for address, data in enumerate(rows):
            # 复用前面的 write()，把每个元素依次写到对应地址。
            self.write(address, data)

    # display() 用日志把内存内容打印成表格，便于人工查看。
    # rows 表示想打印前多少行，decimal=True 表示默认按十进制显示。
    def display(self, rows, decimal=True):
        # 先打印一个空行，让日志视觉上和前后内容隔开。
        logger.info("\n")
        # self.name.upper() 会把名字转成大写，例如 data 变成 DATA。
        logger.info(f"{self.name.upper()} MEMORY")

        # 这里估算表格宽度；8*2 表示给两列各预留 8 个字符，再额外补 3 个边框字符。
        table_size = (8 * 2) + 3
        # 打印表格顶边；字符串乘法 "-" * N 表示把横线重复 N 次。
        logger.info("+" + "-" * (table_size - 3) + "+")

        # 表头固定是地址列和数据列。
        header = "| Addr | Data "
        # 用空格把表头补齐到统一宽度，再补上右边框。
        logger.info(header + " " * (table_size - len(header) - 1) + "|")

        # 再打印一条分隔线，把表头和数据区隔开。
        logger.info("+" + "-" * (table_size - 3) + "+")
        # enumerate(self.memory) 表示按“地址 + 数据值”的形式遍历整块软件内存。
        for i, data in enumerate(self.memory):
            # 只打印用户要求的前 rows 行，避免日志太长。
            if i < rows:
                # 如果 decimal 为 True，就按十进制打印，更适合看普通数值。
                if decimal:
                    # f-string 里的 :<4 表示左对齐并占 4 个字符宽度。
                    row = f"| {i:<4} | {data:<4}"
                    # 补足右侧空格并补上边框，让每一行长度一致。
                    logger.info(row + " " * (table_size - len(row) - 1) + "|")
                else:
                    # 如果要看二进制，就把数据格式化成固定 16 bit 宽度。
                    data_bin = format(data, f"0{16}b")
                    # 组成二进制显示行；这里直接把右边框也拼进字符串里。
                    row = f"| {i:<4} | {data_bin} |"
                    # 同样做右侧补空格，保持表格整齐。
                    logger.info(row + " " * (table_size - len(row) - 1) + "|")
        # 打印表格底边，表示这次显示结束。
        logger.info("+" + "-" * (table_size - 3) + "+")
