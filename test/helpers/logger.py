import datetime


# 这是一个非常轻量的日志工具。
# 它没有依赖 Python 标准 logging 模块，而是直接把字符串追加写进 test/logs 目录下的文件。
# 好处是简单直接，测试脚本后面还能重新打开同一个日志文件做正则匹配检查。
class Logger:
    def __init__(self, level="debug"):
        # 用当前时间生成日志文件名，避免每次测试都覆盖上一次结果。
        self.filename = f"test/logs/log_{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}.txt"
        self.level = level

    def debug(self, *messages):
        # `*messages` 表示可变参数，调用时可以一次传很多段消息进来。
        if self.level == "debug":
            self.info(*messages)

    def info(self, *messages):
        # 把所有参数先转成字符串，再用空格拼成一整行。
        full_message = ' '.join(str(message) for message in messages)
        # 以追加模式打开文件，这样每次写日志都会接在文件末尾。
        with open(self.filename, "a") as log_file:
            log_file.write(full_message + "\n")


# 模块级单例，其他文件 `from .logger import logger` 后都共用这一份 logger。
logger = Logger(level="debug")