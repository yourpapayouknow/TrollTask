// 沿用原工程的300毫秒自动唤起流程。
setTimeout(() => {
  // 打开本页安装链接对应的TrollStore入口。
  window.location.href = document.getElementById("install").href;
}, 300);
