<template>
  <div class="page">
    <aside class="sidebar" v-if="user">
      <input class="search" v-model="search" type="text" placeholder="Search" />
      <Calendar
        class="calendar"
        :attributes="attrs"
        @dayclick="onDayClick"
        @did-move="onDidMove"
      />
    </aside>
    <main class="content">
      <div class="userbar" v-if="user" @mouseenter="showSignout=true" @mouseleave="showSignout=false">
        <span class="email">{{ user.email }}</span>
        <div class="signout-pop" v-if="showSignout">
          <button class="signout" @click="signOut">退出登录</button>
        </div>
      </div>

      <section v-if="!user" class="auth">
        <h3>登录</h3>
        <input v-model="email" type="email" placeholder="邮箱" />
        <input v-model="password" type="password" placeholder="密码" />
        <div class="auth-actions">
          <button @click="signIn">登录</button>
          <button @click="signUp">注册</button>
        </div>
      </section>

      <section v-if="filterDate && user" class="date-banner">
        <span class="date-text">{{ labelForDateStr(filterDate) }}</span>
        <button class="date-close" @click="clearFilter">×</button>
      </section>
      <section class="editor" v-if="user">
        <textarea class="input" v-model="form.content" placeholder="" />
        <div class="toolbar">
          <input ref="fileInput" type="file" multiple accept="image/*" @change="onFiles" />
          <el-radio-group class="compact-radio" v-model="form.type">
            <el-radio label="sleep">睡眠</el-radio>
            <el-radio label="exercise">运动</el-radio>
            <el-radio label="meditation">冥想</el-radio>
          </el-radio-group>
          <el-rate v-model="form.score" :max="5" />          
          <button class="save" :class="{ active: (form.content || '').trim().length > 0 }" @click="save">保存</button>
        </div>
      </section>
      <section class="list" v-if="user">
        <article v-for="n in filteredNotes" :key="n.id" class="note">
          <header class="note-header">
            <span>{{ formatHeader(n.entry_date, n.created_at) }}</span>
            <span class="actions" role="button" @click.stop="toggleMenu(n.id)">⋮</span>
          </header>
          <div class="menu" v-if="openMenuId===n.id" @click.stop>
            <button @click="startEdit(n)">编辑</button>
            <button @click="remove(n)">删除</button>
          </div>
          <div class="note-body">
            <p class="text">{{ n.content }}</p>
            <div class="images" v-if="n.images && n.images.length">
              <img v-for="p in n.images" :key="p" :src="signedUrlMap[p] || ''" @click="openPreview(signedUrlMap[p] || '')" />
            </div>
          </div>
        </article>
        <img style="width: 120px;height: 120px;margin: 0 auto;padding-top: 30px;" src="./assets/nodata.svg" v-if="filteredNotes.length === 0">
      </section>
    </main>
    <div class="modal" v-if="editing">
      <div class="dialog">
        <h3>编辑笔记</h3>
        <div class="row">
          <textarea v-model="editForm.content" class="input"></textarea>
        </div>
        <div class="row">
          <el-radio-group class="compact-radio" v-model="editForm.type">
            <el-radio label="sleep">睡眠</el-radio>
            <el-radio label="exercise">运动</el-radio>
            <el-radio label="meditation">冥想</el-radio>
          </el-radio-group>
          <el-rate v-model="editForm.score" :max="5" />
        </div>
        <div class="row">
          <div class="images" v-if="editForm.images && editForm.images.length">
            <div class="img-wrap" v-for="p in editForm.images" :key="p">
              <img :src="signedUrlMap[p] || ''" />
              <button class="img-remove" @click="removeEditImage(p)">删除</button>
            </div>
          </div>
          <input type="file" multiple accept="image/*" @change="onEditFiles" />
        </div>
        <div class="row">
          <label>创建日期</label>
          <input type="date" v-model="editForm.created_date" />
          <input type="time" v-model="editForm.created_time" />
        </div>
        <div class="actions">
          <button @click="applyEdit">保存</button>
          <button @click="cancelEdit">取消</button>
        </div>
      </div>
    </div>
    <div class="modal" v-if="loading">
      <div class="dialog">
        <h3>处理中</h3>
        <div class="row">
          <span>图片压缩与上传中，请稍候…</span>
        </div>
      </div>
    </div>
    <div class="preview" v-if="previewOpen" @click.self="closePreview">
      <img :src="previewUrl" />
      <button class="preview-close" @click="closePreview">关闭</button>
    </div>
  </div>
</template>

<script setup>
import { Calendar } from 'v-calendar'
import 'v-calendar/style.css'
import { ref, computed, onMounted } from 'vue'
import { supabase } from './lib/supabase'
import { processImage } from './utils/imageProcessor'

const selectedDate = ref(new Date())
const attrs = ref([{ key: 'today', highlight: true, dates: new Date() }])
const search = ref('')
const email = ref('')
const password = ref('')
const user = ref(null)
const openMenuId = ref(null)
const editing = ref(null)
const editForm = ref({ content: '', type: 'sleep', score: 5, is_private: true, created_date: '', created_time: '', images: [] })
const editFiles = ref([])
const editRemoved = ref([])
const filterDate = ref(null)
const monthDate = ref(new Date())
const showSignout = ref(false)
const loading = ref(false)

const form = ref({
  content: '',
  images: [],
  type: 'sleep',
  score: 5,
  is_private: true
})

const files = ref([])
const fileInput = ref(null)
const notes = ref([])
const signedUrlMap = ref({})
const previewOpen = ref(false)
const previewUrl = ref('')

function openPreview(url) {
  previewUrl.value = url || ''
  previewOpen.value = !!previewUrl.value
}

function closePreview() {
  previewOpen.value = false
  previewUrl.value = ''
}
const blue6 = ['#e6f0ff', '#cfe3ff', '#a9ceff', '#7fb2ff', '#3d8aff', '#1677ff']
const orange6 = ['#fff2e6', '#ffd9b3', '#ffbf80', '#ffa64d', '#ff9933', '#ff8c00']
const purple6 = ['#f0eaff', '#e0d1ff', '#c2a8ff', '#a27dff', '#9559f2', '#8a2be2']

function ymd(d) {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function ymdToDate(s) {
  if (!s) return null
  const [y, m, d] = String(s).split('-').map(x => parseInt(x, 10))
  if (!y || !m || !d) return null
  return new Date(y, m - 1, d)
}

function weekdayZh(d) {
  const w = d.getDay()
  const map = ['星期日','星期一','星期二','星期三','星期四','星期五','星期六']
  return map[w]
}

function formatHeader(entryDate, createdAt) {
  const dateObj = ymdToDate(entryDate) || new Date(createdAt)
  const timeObj = new Date(createdAt)
  const y = dateObj.getFullYear()
  const m = String(dateObj.getMonth() + 1).padStart(2, '0')
  const day = String(dateObj.getDate()).padStart(2, '0')
  const hh = String(timeObj.getHours()).padStart(2, '0')
  const mm = String(timeObj.getMinutes()).padStart(2, '0')
  return `${y}-${m}-${day} ${hh}:${mm} ${weekdayZh(dateObj)}`
}

async function loadNotes(opts) {
  let q = supabase
    .from('notes')
    .select('id,title,content,images,type,score,created_at,is_private,user_id,entry_date')
    .is('deleted_at', null)
    .order('entry_date', { ascending: false })
  if (user.value?.id) q = q.eq('user_id', user.value.id)
  const startParam = opts?.start
  const endParam = opts?.end
  const singleDate = opts?.date
  if (singleDate) {
    q = q.eq('entry_date', singleDate)
  } else if (startParam && endParam) {
    q = q.gte('entry_date', startParam).lte('entry_date', endParam)
  } else if (filterDate.value) {
    q = q.eq('entry_date', filterDate.value)
  } else {
    const start = new Date(monthDate.value.getFullYear(), monthDate.value.getMonth(), 1)
    const end = new Date(monthDate.value.getFullYear(), monthDate.value.getMonth() + 1, 0)
    q = q.gte('entry_date', ymd(start)).lte('entry_date', ymd(end))
  }
  const { data } = await q
  notes.value = data || []
  await refreshSignedUrls()
  await rebuildCalendarAttrs()
}

async function refreshSignedUrls() {
  const all = new Set()
  notes.value.forEach(n => (n.images || []).forEach(p => all.add(p)))
  const bucket = 'note-images'
  for (const path of all) {
    if (signedUrlMap.value[path]) continue
    const { data } = await supabase.storage.from(bucket).createSignedUrl(path, 60 * 60)
    signedUrlMap.value[path] = data?.signedUrl || ''
  }
}

function normalizeEventDate(evt) {
  const v = (evt && (evt.date ?? evt.startDate)) ?? evt
  const d = v instanceof Date ? v : new Date(v)
  if (isNaN(d.getTime())) return null
  return d
}

function onDayClick(e) {
  const d = normalizeEventDate(e)
  if (!d) {
    window.alert('日期解析失败')
    return
  }
  selectedDate.value = d
  filterDate.value = ymd(d)
}

function onDidMove(pages) {
  const arr = Array.isArray(pages) ? pages : [pages]
  const p = arr[0]
  if (!p || !p.year || !p.month) return
  const d = new Date(p.year, p.month - 1, 1)
  monthDate.value = d
  filterDate.value = null
  const start = ymd(new Date(d.getFullYear(), d.getMonth(), 1))
  const end = ymd(new Date(d.getFullYear(), d.getMonth() + 1, 0))
  loadNotes({ start, end })
}

function onFiles(ev) {
  const input = ev.target
  files.value = Array.from(input?.files || [])
}

async function uploadImagesForDate() {
  if (!files.value.length) return []
  const { data: u } = await supabase.auth.getUser()
  const uid = u?.user?.id
  if (!uid) {
    window.alert('请先登录后再上传图片与保存日记')
    return []
  }
  const d = selectedDate.value
  const monthFolder = `${uid}/${String(d.getFullYear())}/${String(d.getMonth() + 1).padStart(2, '0')}`
  const bucket = 'note-images'
  const paths = []
  loading.value = true
  try {
    for (const f of files.value) {
      const pf = await processImage(f)
      const ext = pf.name.split('.').pop() || 'webp'
      const p = `${monthFolder}/${crypto.randomUUID()}.${ext}`
      const { error } = await supabase.storage.from(bucket).upload(p, pf, { upsert: false })
      if (error) throw new Error(error.message || '图片上传失败')
      paths.push(p)
    }
    return paths
  } finally {
    loading.value = false
  }
}

async function save() {
  try {
    const { data: u } = await supabase.auth.getUser()
    const uid = u?.user?.id
    if (!uid) {
      window.alert('请先登录后再保存日记')
      return
    }
    const dateStr = ymd(selectedDate.value)
    const type = form.value.type
    const conflict = await hasConflict(dateStr, type, null)
    if (conflict) {
      window.alert('该日期已存在该类型的记录，无法重复记录')
      return
    }
    const paths = await uploadImagesForDate()
    const payload = {
      content: form.value.content,
      images: paths,
      type: form.value.type,
      score: form.value.score,
      is_private: form.value.is_private,
      entry_date: dateStr,
      user_id: uid
    }
    const { error } = await supabase.from('notes').insert(payload)
    if (error) throw new Error(error.message || '保存失败')
    form.value.content = ''
    form.value.score = 5
    files.value = []
    if (fileInput.value) fileInput.value.value = ''
    await loadNotes()
  } catch (e) {
    const msg = (e && e.message) ? e.message : '保存失败'
    window.alert(msg)
  }
}

function datePart(ts) {
  const d = new Date(ts)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function timePart(ts) {
  const d = new Date(ts)
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return `${hh}:${mm}`
}

function toggleMenu(id) {
  openMenuId.value = openMenuId.value === id ? null : id
}

function startEdit(n) {
  openMenuId.value = null
  editing.value = n
  editForm.value = {
    content: n.content || '',
    type: n.type || 'sleep',
    score: n.score || 5,
    is_private: n.is_private,
    created_date: datePart(n.created_at),
    created_time: timePart(n.created_at),
    images: (n.images || []).slice()
  }
  editFiles.value = []
  editRemoved.value = []
  ensureSignedFor(editForm.value.images)
}

function onEditFiles(ev) {
  const input = ev.target
  editFiles.value = Array.from(input?.files || [])
}

function removeEditImage(p) {
  editForm.value.images = (editForm.value.images || []).filter(x => x !== p)
  editRemoved.value.push(p)
}

async function ensureSignedFor(paths) {
  const bucket = 'note-images'
  for (const path of paths || []) {
    if (signedUrlMap.value[path]) continue
    const { data } = await supabase.storage.from(bucket).createSignedUrl(path, 60 * 60)
    signedUrlMap.value[path] = data?.signedUrl || ''
  }
}

async function applyEdit() {
  const { data: u } = await supabase.auth.getUser()
  const uid = u?.user?.id
  if (!uid || !editing.value) return
  const created = new Date(`${editForm.value.created_date}T${(editForm.value.created_time || '00:00')}:00`)
  const dateStr = ymd(created)
  const type = editForm.value.type
  const dup = await hasConflict(dateStr, type, editing.value.id)
  if (dup) {
    window.alert('该日期已存在该类型的记录，无法修改为重复类型')
    return
  }
  const bucket = 'note-images'
  const monthFolder = `${uid}/${String(created.getFullYear())}/${String(created.getMonth() + 1).padStart(2, '0')}`
  const newPaths = []
  loading.value = true
  try {
    for (const f of editFiles.value) {
      const pf = await processImage(f)
      const ext = pf.name.split('.').pop() || 'webp'
      const p = `${monthFolder}/${crypto.randomUUID()}.${ext}`
      await supabase.storage.from(bucket).upload(p, pf, { upsert: false })
      newPaths.push(p)
    }
    const finalImages = (editForm.value.images || []).concat(newPaths)
    const payload = {
      content: editForm.value.content,
      type: editForm.value.type,
      score: editForm.value.score,
      is_private: editForm.value.is_private,
      entry_date: dateStr,
      created_at: created.toISOString(),
      images: finalImages
    }
    await supabase.from('notes').update(payload).eq('id', editing.value.id).eq('user_id', uid)
    if (editRemoved.value.length) {
      await supabase.storage.from(bucket).remove(editRemoved.value)
    }
    editing.value = null
    editFiles.value = []
    editRemoved.value = []
    await loadNotes()
  } finally {
    loading.value = false
  }
}

function cancelEdit() { editing.value = null }

async function remove(n) {
  const { data: u } = await supabase.auth.getUser()
  const uid = u?.user?.id
  if (!uid) return
  openMenuId.value = null
  await supabase.from('notes').update({ deleted_at: new Date().toISOString() }).eq('id', n.id).eq('user_id', uid)
  await loadNotes()
}

const filteredNotes = computed(() => {
  let list = notes.value
  if (filterDate.value) list = list.filter(n => n.entry_date === filterDate.value)
  const q = search.value.trim()
  if (q) list = list.filter(n => (n.content || '').includes(q) || (n.title || '').includes(q))
  return list
})

onMounted(async () => {
  const { data } = await supabase.auth.getUser()
  user.value = data?.user || null
  if (user.value) await ensureProfile()
  await loadNotes()
  supabase.auth.onAuthStateChange((_evt, session) => {
    user.value = session?.user || null
    if (user.value) ensureProfile()
    loadNotes()
  })
})

function clearFilter() {
  filterDate.value = null
  loadNotes()
}

function labelForDateStr(s) {
  const d = new Date(s)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day} ${weekdayZh(d)}`
}

async function ensureProfile() {
  const uid = user.value?.id
  if (!uid) return
  await supabase.from('profiles').upsert({ id: uid })
}

async function hasConflict(dateStr, type, excludeId) {
  const { data: u } = await supabase.auth.getUser()
  const uid = u?.user?.id
  if (!uid) return false
  const { data } = await supabase
    .from('notes')
    .select('id')
    .eq('user_id', uid)
    .eq('entry_date', dateStr)
    .eq('type', type)
    .is('deleted_at', null)
  const list = data || []
  return list.some(x => x.id !== excludeId)
}

async function rebuildCalendarAttrs() {
  const sleepGroups = [[], [], [], [], [], []]
  const exerciseGroups = [[], [], [], [], [], []]
  const meditationGroups = [[], [], [], [], [], []]
  for (const n of notes.value || []) {
    const s = n.entry_date
    if (!s) continue
    const idx = Math.min(5, Math.max(0, Number(n.score ?? 0)))
    const d = ymdToDate(s)
    if (!d) continue
    if (n.type === 'sleep') sleepGroups[idx].push(d)
    else if (n.type === 'exercise') exerciseGroups[idx].push(d)
    else if (n.type === 'meditation') meditationGroups[idx].push(d)
  }
  const todayAttr = { key: 'today', highlight: true, dates: new Date() }
  const attrsList = [todayAttr]
  for (let i = 0; i < 6; i++) {
    if (sleepGroups[i].length) attrsList.push({ key: `dot-sleep-${i}`, dot: { style: { backgroundColor: blue6[i] } }, dates: sleepGroups[i] })
    if (exerciseGroups[i].length) attrsList.push({ key: `dot-exercise-${i}`, dot: { style: { backgroundColor: orange6[i] } }, dates: exerciseGroups[i] })
    if (meditationGroups[i].length) attrsList.push({ key: `dot-meditation-${i}`, dot: { style: { backgroundColor: purple6[i] } }, dates: meditationGroups[i] })
  }
  attrs.value = attrsList
}

async function signIn() {
  const { error } = await supabase.auth.signInWithPassword({ email: email.value, password: password.value })
  if (error) window.alert(error.message)
}

async function signUp() {
  const { error } = await supabase.auth.signUp({ email: email.value, password: password.value })
  if (error) window.alert(error.message)
  else window.alert('已发送验证邮件')
}

async function signOut() {
  await supabase.auth.signOut()
  notes.value = []
  await rebuildCalendarAttrs()
}
</script>

<style scoped>
.page { display: grid; grid-template-columns: 275px 1fr; height: 100%; background: #f7f6f2; }
.sidebar { border-right: 1px solid #e0dfda; padding: 12px; height: 400px; }
.search { width: 100%; box-sizing: border-box; border: 1px solid #ddd; border-radius: 6px; padding: 8px; margin-bottom: 8px; }
.calendar { width: 100%; height: 100%; }
.content { padding: 16px; }
.date-banner { display: flex; gap: 8px; align-items: center; background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 8px 12px; margin-bottom: 8px; }
.date-text { color: #555; }
.date-close { background: #bbb; color: #fff; border: none; border-radius: 6px; padding: 6px 10px; }
.userbar { position: fixed; right: 12px; top: 12px; display: flex; align-items: center; gap: 8px; z-index: 100; }
.email { color: #666; }
.signout { background: #bbb; color: #fff; border: none; border-radius: 6px; padding: 6px 10px; }
.signout-pop { position: absolute; right: 0; top: 100%; background: #fff; border: 1px solid #ddd; border-radius: 6px; padding: 6px 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
.auth { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 12px; max-width: 420px; }
.auth h3 { margin: 0 0 8px; }
.auth input { width: 100%; box-sizing: border-box; border: 1px solid #ddd; border-radius: 6px; padding: 8px; margin-bottom: 8px; }
.auth-actions { display: flex; gap: 8px; justify-content: flex-end; }
.auth-actions button { background: #999; color: #fff; border: none; border-radius: 8px; padding: 8px 14px; }
.editor { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 12px; margin-bottom: 12px; }
.input { width: 100%; min-height: 100px; border: none; outline: none; resize: vertical; }
textarea { background: #f8f8f8; }
.toolbar { display: flex; gap: 8px; align-items: center; justify-content: flex-end; }
.privacy { display: flex; gap: 6px; align-items: center; color: #666; }
.save { background: #999; color: #fff; border: none; border-radius: 8px; padding: 8px 14px; }
.save.active { background: #1677ff; }
.list { display: flex; flex-direction: column; gap: 12px; }
.loading { display: none; }
.sentinel { display: none; }
.note { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 12px; position: relative; }
.note-header { display: flex; justify-content: space-between; color: #555; font-size: 13px; }
.note-header { position: relative; }
.actions { cursor: pointer; }
.note-body { text-align: left; }
.menu { position: absolute; right: 8px; top: 8px; background: #fff; border: 1px solid #ddd; border-radius: 6px; padding: 6px; display: flex; flex-direction: column; gap: 6px; z-index: 10; }
.menu button { background: #eee; border: none; padding: 6px 8px; border-radius: 4px; }
.text { white-space: pre-wrap; }
.images { display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 8px; margin-top: 8px; }
.images img { width: 100%; height: 120px; object-fit: cover; border-radius: 6px; }
.preview { position: fixed; inset: 0; background: rgba(0,0,0,0.8); display: flex; align-items: center; justify-content: center; z-index: 1000; }
.preview img { max-width: 90vw; max-height: 90vh; object-fit: contain; border-radius: 8px; box-shadow: 0 6px 24px rgba(0,0,0,0.3); }
.preview-close { position: fixed; right: 16px; top: 16px; background: rgba(255,255,255,0.9); color: #333; border: none; border-radius: 20px; padding: 8px 12px; z-index: 1001; }
.modal { position: fixed; inset: 0; background: rgba(0,0,0,0.3); display: flex; align-items: center; justify-content: center; }
.dialog { background: #fff; width: 600px; max-width: 90%; border: 1px solid #ddd; border-radius: 8px; padding: 12px; }
.dialog .row { display: flex; gap: 8px; align-items: center; margin-bottom: 8px; }
.dialog .actions { display: flex; gap: 8px; justify-content: flex-end; }
.img-wrap { position: relative; }
.img-wrap img { width: 120px; height: 120px; object-fit: cover; border-radius: 6px; }
.img-remove { position: absolute; right: 4px; top: 4px; background: rgba(0,0,0,0.5); color: #fff; border: none; border-radius: 4px; padding: 2px 6px; }
.compact-radio .el-radio { margin-right: 8px; }
.compact-radio .el-radio:last-child { margin-right: 0; }
@media (max-width: 768px) {
  .page { grid-template-columns: 1fr; }
  .sidebar { border-right: none; border-bottom: 1px solid #e0dfda; height: auto; }
  .calendar { width: 100%; height: auto; }
  .content { padding: 12px; }
  .userbar { position: relative; right: auto; top: auto; background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 8px 12px; margin-bottom: 8px; }
  .toolbar { flex-wrap: wrap; justify-content: space-between; }
  .auth { max-width: 100%; }
  .date-banner { flex-wrap: wrap; }
  .images { grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); }
  .images img { height: 100px; }
  .dialog { width: 100%; max-width: 100%; margin: 0 12px; }
  .dialog .row { flex-wrap: wrap; }
}
@media (max-width: 480px) {
  .content { padding: 8px; }
  .input { min-height: 80px; }
  .note { padding: 10px; }
  .note-header { font-size: 12px; }
  .images { grid-template-columns: repeat(auto-fill, minmax(90px, 1fr)); }
  .images img { height: 90px; }
  .dialog { max-height: 90vh; overflow: auto; padding: 10px; }
  .auth-actions { justify-content: space-between; }
}
</style>
