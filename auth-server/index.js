const fs = require('fs')
const path = require('path')
const express = require('express')
const session = require('express-session')
const bcrypt = require('bcrypt')
const mysql = require('mysql2')
const app = express()
const rateLimit = require('express-rate-limit')
const port = 3000

const db = mysql.createConnection({
    host: 'localhost',
    user: '__DB_USER__',
    password: '__DB_PASS__',
    database: 'portal',
    socketPath: '/var/run/mysqld/mysqld.sock'
})

db.connect((err) => {
    if (err) { console.error('DB connection failed:', err); process.exit(1) }
    console.log('Connected to database')
})

app.use(express.urlencoded({ extended: true }))
app.use(express.json())
app.set('trust proxy', 1)

app.use(session({
    secret: '__SESSION_SECRET__',
    resave: false,
    saveUninitialized: false,
    cookie: {
        maxAge: 1000 * 60 * 60 * 6,
        httpOnly: true,
        secure: false,
        sameSite: 'lax',
        domain: '.__DOMAIN__'
    }
}))

app.get('/auth/check', (req, res) => {
    if (req.session && req.session.userId) return res.sendStatus(200)
    res.sendStatus(401)
})

const loginLimiter = rateLimit({
    windowMs: 3 * 60 * 1000,
    max: 3,
    message: 'Demasiados intentos, espera 3 minutos'
})

app.get('/login', (req, res) => {
    if (req.session && req.session.userId) return res.redirect('/')
    const redirect = req.query.redirect || '/'
    const error = req.query.error ? 'Usuario o contraseña incorrectos' : ''
    let html = fs.readFileSync(path.join('/var/www/html/portal', 'login.html'), 'utf8')
    html = html.replace('</form>', `<input type="hidden" name="redirect" value="${redirect}"></form>`)
    html = html.replace('<p id="error"></p>', `<p id="error">${error}</p>`)
    res.send(html)
})

app.post('/login', loginLimiter, (req, res) => {
    const { username, password } = req.body
    db.query('SELECT * FROM users WHERE username = ?', [username], (err, results) => {
        if (err) return res.sendStatus(500)
        if (results.length === 0) return res.redirect('/login?error=1&redirect=' + encodeURIComponent(req.body.redirect || '/'))
        bcrypt.compare(password, results[0].password_hash)
            .then(match => {
                if (!match) return res.redirect('/login?error=1&redirect=' + encodeURIComponent(req.body.redirect || '/'))
                req.session.userId = results[0].id
                req.session.save(() => {
                    const redirect = req.body.redirect || '/'
                    const safeRedirect = redirect.startsWith('https://') && redirect.includes('.__DOMAIN__') ? redirect : '/'
                    res.redirect(safeRedirect)
                })
            })
            .catch((err) => { res.sendStatus(500) })
    })
})

app.get('/logout', (req, res) => {
    req.session.destroy(() => res.redirect('/login'))
})

app.listen(port, () => console.log(`Server de autorización ejecutándose en el puerto ${port}.`))