import { defineUserConfig } from 'vuepress'
import { viteBundler } from '@vuepress/bundler-vite'
import { defaultTheme } from '@vuepress/theme-default'

export default defineUserConfig({
  lang: 'zh-CN',
  title: 'HardwareMonitor 运行教程',
  description: 'macOS 硬件监控应用 HardwareMonitor 的 Xcode 运行教程',
  base: '/HardwareMonitor/tutorial/',
  head: [['link', { rel: 'icon', href: '/HardwareMonitor/tutorial/favicon.svg' }]],
  bundler: viteBundler(),
  theme: defaultTheme({
    navbar: [
      { text: '运行教程', link: '/' },
      { text: 'GitHub', link: 'https://github.com/Wolfzzzzz/HardwareMonitor' },
      { text: '介绍页', link: 'https://wolfzzzzz.github.io/HardwareMonitor/' },
    ],
    sidebar: false,
    editLink: false,
    lastUpdated: false,
    contributors: false,
  }),
})
